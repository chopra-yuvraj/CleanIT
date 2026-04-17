-- ============================================================
--  CleanIT — Initial Database Schema
--  Supabase PostgreSQL Migration
-- ============================================================

-- ────────────────────────────────────────────────────────────
--  1. Extensions
-- ────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ────────────────────────────────────────────────────────────
--  2. Custom Enum Types
-- ────────────────────────────────────────────────────────────
CREATE TYPE user_role AS ENUM ('student', 'cleaner', 'admin');

CREATE TYPE request_status AS ENUM (
    'OPEN',
    'ASSIGNED',
    'IN_PROGRESS',
    'COMPLETED',
    'CANCELLED_ROOM_LOCKED'
);

-- ────────────────────────────────────────────────────────────
--  3. Tables
-- ────────────────────────────────────────────────────────────

-- Users ──────────────────────────────────────────────────────
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    auth_id     UUID UNIQUE,                    -- Links to Supabase auth.users.id
    email       TEXT UNIQUE NOT NULL,
    name        TEXT NOT NULL,
    role        user_role NOT NULL DEFAULT 'student',
    block       TEXT,                            -- Hostel block (A, B, C…)
    room_number TEXT,                            -- Room number (101, 202…)
    fcm_token   TEXT,                            -- Firebase Cloud Messaging token
    is_on_duty  BOOLEAN NOT NULL DEFAULT FALSE,  -- Cleaner availability toggle
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  users IS 'All app users: students, cleaners, and admins.';
COMMENT ON COLUMN users.is_on_duty IS 'Only relevant for cleaners. TRUE = receiving broadcast requests.';

-- Requests ──────────────────────────────────────────────────
CREATE TABLE requests (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status      request_status NOT NULL DEFAULT 'OPEN',
    is_sweeping BOOLEAN NOT NULL DEFAULT FALSE,
    is_mopping  BOOLEAN NOT NULL DEFAULT FALSE,
    is_urgent   BOOLEAN NOT NULL DEFAULT FALSE,
    notes       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE requests IS 'Cleaning requests created by students.';

-- Assignments ───────────────────────────────────────────────
CREATE TABLE assignments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id      UUID NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
    cleaner_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assigned_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    failure_reason  TEXT,
    proof_image_url TEXT,
    CONSTRAINT uq_one_assignment_per_request UNIQUE (request_id)
);

COMMENT ON TABLE assignments IS 'Links a request to the cleaner who accepted it. Max one per request.';

-- Feedback ──────────────────────────────────────────────────
CREATE TABLE feedback (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id  UUID NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
    student_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating      INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment     TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_one_feedback_per_request UNIQUE (request_id)
);

COMMENT ON TABLE feedback IS 'Post-completion 1-5 star rating from the student.';

-- ────────────────────────────────────────────────────────────
--  4. Indexes
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_requests_student_id  ON requests(student_id);
CREATE INDEX idx_requests_status      ON requests(status);
CREATE INDEX idx_assignments_cleaner  ON assignments(cleaner_id);
CREATE INDEX idx_users_role           ON users(role);
CREATE INDEX idx_users_on_duty        ON users(is_on_duty) WHERE is_on_duty = TRUE;
CREATE INDEX idx_users_fcm            ON users(fcm_token)  WHERE fcm_token IS NOT NULL;

-- ★ Critical: Only ONE active request per student at any time.
--   This is enforced at the database level so no application-layer race can bypass it.
CREATE UNIQUE INDEX idx_one_active_request_per_student
    ON requests(student_id)
    WHERE status IN ('OPEN', 'ASSIGNED', 'IN_PROGRESS');

-- ────────────────────────────────────────────────────────────
--  5. Auto-update `updated_at` Trigger
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_requests_updated_at
    BEFORE UPDATE ON requests
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ────────────────────────────────────────────────────────────
--  6. RPC Functions (called from Edge Functions)
-- ────────────────────────────────────────────────────────────

-- ★ accept_request ──────────────────────────────────────────
--   Atomic, race-condition-safe job acceptance.
--   Uses FOR UPDATE SKIP LOCKED so concurrent callers don't block;
--   the loser simply gets zero rows and a friendly rejection.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION accept_request(
    p_request_id UUID,
    p_cleaner_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_request  RECORD;
    v_assign   RECORD;
    v_cleaner  RECORD;
BEGIN
    -- 1. Verify caller is a cleaner
    SELECT * INTO v_cleaner FROM users WHERE id = p_cleaner_id AND role = 'cleaner';
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'code',    'FORBIDDEN',
            'message', 'Only cleaners can accept requests.'
        );
    END IF;

    -- 2. Lock the request row — SKIP LOCKED means losers see 0 rows instantly
    SELECT * INTO v_request
    FROM requests
    WHERE id = p_request_id AND status = 'OPEN'
    FOR UPDATE SKIP LOCKED;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'code',    'ALREADY_ASSIGNED',
            'message', 'This request was already accepted by someone else.'
        );
    END IF;

    -- 3. Transition status to ASSIGNED
    UPDATE requests
    SET    status = 'ASSIGNED'
    WHERE  id = p_request_id;

    -- 4. Create the assignment record
    INSERT INTO assignments (request_id, cleaner_id, assigned_at)
    VALUES (p_request_id, p_cleaner_id, NOW())
    RETURNING * INTO v_assign;

    -- 5. Return success payload
    RETURN jsonb_build_object(
        'success',       TRUE,
        'assignment_id', v_assign.id,
        'message',       'Request accepted successfully.'
    );
END;
$$;

-- ★ report_room_locked ──────────────────────────────────────
--   Cancels a request because the room was locked / student absent.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION report_room_locked(
    p_request_id     UUID,
    p_cleaner_id     UUID,
    p_failure_reason TEXT DEFAULT 'room_locked',
    p_proof_url      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_assignment RECORD;
    v_student_id UUID;
BEGIN
    -- 1. Verify the cleaner is actually assigned to this request
    SELECT a.*, r.student_id INTO v_assignment
    FROM assignments a
    JOIN requests r ON r.id = a.request_id
    WHERE a.request_id = p_request_id
      AND a.cleaner_id = p_cleaner_id
      AND r.status IN ('ASSIGNED', 'IN_PROGRESS');

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'code',    'NOT_ASSIGNED_CLEANER',
            'message', 'You are not the assigned cleaner for this request, or the request is not active.'
        );
    END IF;

    v_student_id := v_assignment.student_id;

    -- 2. Update request status
    UPDATE requests
    SET    status = 'CANCELLED_ROOM_LOCKED'
    WHERE  id = p_request_id;

    -- 3. Update assignment with failure details
    UPDATE assignments
    SET    failure_reason  = p_failure_reason,
           proof_image_url = p_proof_url,
           completed_at    = NOW()
    WHERE  request_id = p_request_id;

    -- 4. Return success + student_id (so edge function can send FCM)
    RETURN jsonb_build_object(
        'success',    TRUE,
        'student_id', v_student_id,
        'message',    'Request cancelled. Student will be notified.'
    );
END;
$$;

-- ★ start_job ───────────────────────────────────────────────
--   Cleaner taps "Start Job" — transitions ASSIGNED → IN_PROGRESS
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION start_job(
    p_request_id UUID,
    p_cleaner_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Verify assignment exists and request is ASSIGNED
    IF NOT EXISTS (
        SELECT 1 FROM assignments a
        JOIN requests r ON r.id = a.request_id
        WHERE a.request_id = p_request_id
          AND a.cleaner_id = p_cleaner_id
          AND r.status = 'ASSIGNED'
    ) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'code',    'INVALID_STATE',
            'message', 'Cannot start this job.'
        );
    END IF;

    UPDATE requests SET status = 'IN_PROGRESS' WHERE id = p_request_id;
    UPDATE assignments SET started_at = NOW() WHERE request_id = p_request_id;

    RETURN jsonb_build_object('success', TRUE, 'message', 'Job started.');
END;
$$;

-- ★ complete_job ────────────────────────────────────────────
--   QR verified — transitions IN_PROGRESS → COMPLETED
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION complete_job(
    p_request_id UUID,
    p_cleaner_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM assignments a
        JOIN requests r ON r.id = a.request_id
        WHERE a.request_id = p_request_id
          AND a.cleaner_id = p_cleaner_id
          AND r.status = 'IN_PROGRESS'
    ) THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'code',    'INVALID_STATE',
            'message', 'Cannot complete this job.'
        );
    END IF;

    UPDATE requests SET status = 'COMPLETED' WHERE id = p_request_id;
    UPDATE assignments SET completed_at = NOW() WHERE request_id = p_request_id;

    RETURN jsonb_build_object('success', TRUE, 'message', 'Job completed!');
END;
$$;

-- ────────────────────────────────────────────────────────────
--  7. Row Level Security (RLS)
-- ────────────────────────────────────────────────────────────
ALTER TABLE users       ENABLE ROW LEVEL SECURITY;
ALTER TABLE requests    ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback    ENABLE ROW LEVEL SECURITY;

-- Users — everyone can read, only self can update
CREATE POLICY "users_select_all"  ON users FOR SELECT USING (TRUE);
CREATE POLICY "users_update_self" ON users FOR UPDATE USING (auth.uid()::text = auth_id::text);

-- Requests — students see own, cleaners/admins see all
CREATE POLICY "requests_select" ON requests FOR SELECT USING (
    student_id IN (SELECT id FROM users WHERE auth_id = auth.uid())
    OR EXISTS (SELECT 1 FROM users WHERE auth_id = auth.uid() AND role IN ('cleaner', 'admin'))
);
CREATE POLICY "requests_insert" ON requests FOR INSERT WITH CHECK (
    student_id IN (SELECT id FROM users WHERE auth_id = auth.uid() AND role = 'student')
);

-- Assignments — involved parties + admins
CREATE POLICY "assignments_select" ON assignments FOR SELECT USING (
    cleaner_id IN (SELECT id FROM users WHERE auth_id = auth.uid())
    OR request_id IN (SELECT id FROM requests WHERE student_id IN (SELECT id FROM users WHERE auth_id = auth.uid()))
    OR EXISTS (SELECT 1 FROM users WHERE auth_id = auth.uid() AND role = 'admin')
);

-- Feedback — student can insert for own completed requests
CREATE POLICY "feedback_insert" ON feedback FOR INSERT WITH CHECK (
    student_id IN (SELECT id FROM users WHERE auth_id = auth.uid())
    AND EXISTS (
        SELECT 1 FROM requests WHERE id = request_id AND status = 'COMPLETED'
        AND student_id IN (SELECT id FROM users WHERE auth_id = auth.uid())
    )
);
CREATE POLICY "feedback_select" ON feedback FOR SELECT USING (TRUE);

-- ────────────────────────────────────────────────────────────
--  8. Supabase Realtime Publication
--     Enables live subscriptions for request status changes
-- ────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE requests;
ALTER PUBLICATION supabase_realtime ADD TABLE assignments;
