// ============================================================
//  CleanIT — Database Seeder Script
// ============================================================
//  Run: node scripts/seed.js
//
//  Creates a rich dataset of users, requests, assignments,
//  feedback, and audit logs for analytics demos and DBMS
//  feature showcasing.
//
//  ★ Generates data across multiple weeks/blocks so that:
//    - Analytics trends show meaningful daily/weekly patterns
//    - Block distribution shows variation across hostel blocks
//    - Cleaner leaderboard shows competitive rankings
//    - Feedback histogram shows all 1-5 star ratings
//    - Task distribution shows sweeping/mopping/both variety
// ============================================================

require('dotenv').config();
const mongoose = require('mongoose');
const User = require('../models/User');
const Request = require('../models/Request');
const Feedback = require('../models/Feedback');
const AuditLog = require('../models/AuditLog');
const connectDB = require('../config/db');

// Helper: random date within the last N days
const daysAgo = (days) => new Date(Date.now() - days * 86400000);
const hoursAfter = (date, hours) => new Date(date.getTime() + hours * 3600000);
const minutesAfter = (date, mins) => new Date(date.getTime() + mins * 60000);

const seed = async () => {
  await connectDB();
  console.log('🌱 Seeding database...\n');

  // ── Clear existing data ──
  await User.deleteMany({});
  await Request.deleteMany({});
  await Feedback.deleteMany({});
  await AuditLog.deleteMany({});
  console.log('   Cleared all collections.');

  // ══════════════════════════════════════════════════════════
  //  USERS — 10 students, 5 cleaners, 1 admin
  // ══════════════════════════════════════════════════════════

  const students = await User.create([
    { email: 'yuvraj@vit.in',    password: 'password123', name: 'Yuvraj Chopra',   role: 'student', block: 'A', roomNumber: '101' },
    { email: 'rahul@vit.edu',    password: 'password123', name: 'Rahul Sharma',    role: 'student', block: 'A', roomNumber: '203' },
    { email: 'priya@vit.edu',    password: 'password123', name: 'Priya Patel',     role: 'student', block: 'B', roomNumber: '205' },
    { email: 'amit@vit.edu',     password: 'password123', name: 'Amit Kumar',      role: 'student', block: 'A', roomNumber: '302' },
    { email: 'sneha@vit.edu',    password: 'password123', name: 'Sneha Gupta',     role: 'student', block: 'C', roomNumber: '410' },
    { email: 'vikram@vit.edu',   password: 'password123', name: 'Vikram Singh',    role: 'student', block: 'B', roomNumber: '108' },
    { email: 'ananya@vit.edu',   password: 'password123', name: 'Ananya Reddy',    role: 'student', block: 'D', roomNumber: '215' },
    { email: 'karan@vit.edu',    password: 'password123', name: 'Karan Mehta',     role: 'student', block: 'A', roomNumber: '403' },
    { email: 'divya@vit.edu',    password: 'password123', name: 'Divya Nair',      role: 'student', block: 'C', roomNumber: '312' },
    { email: 'rohan@vit.edu',    password: 'password123', name: 'Rohan Joshi',     role: 'student', block: 'D', roomNumber: '102' },
    { email: 'meera@vit.edu',    password: 'password123', name: 'Meera Iyer',      role: 'student', block: 'B', roomNumber: '301' },
  ]);
  console.log(`   ✅ Created ${students.length} students`);

  const cleaners = await User.create([
    { email: 'ravi@cleanit.com',   password: 'password123', name: 'Ravi Verma',   role: 'cleaner', isOnDuty: true },
    { email: 'sunita@cleanit.com', password: 'password123', name: 'Sunita Devi',  role: 'cleaner', isOnDuty: true },
    { email: 'mohan@cleanit.com',  password: 'password123', name: 'Mohan Lal',    role: 'cleaner', isOnDuty: false },
    { email: 'geeta@cleanit.com',  password: 'password123', name: 'Geeta Rani',   role: 'cleaner', isOnDuty: true },
    { email: 'rajesh@cleanit.com', password: 'password123', name: 'Rajesh Yadav', role: 'cleaner', isOnDuty: false },
  ]);
  console.log(`   ✅ Created ${cleaners.length} cleaners`);

  const admins = await User.create([
    { email: 'admin@cleanit.com', password: 'admin123', name: 'Admin User', role: 'admin' },
  ]);
  console.log(`   ✅ Created ${admins.length} admin`);

  // ══════════════════════════════════════════════════════════
  //  REQUESTS — 25 requests across 3 weeks
  //  Mix of COMPLETED, CANCELLED, OPEN, ASSIGNED, IN_PROGRESS
  // ══════════════════════════════════════════════════════════

  const requestData = [
    // ── Week 1 (21-14 days ago) — 8 completed requests ──
    {
      studentId: students[0]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: true, isUrgent: false,
      notes: 'Please clean the floor and mop thoroughly, especially under the bed',
      studentName: students[0].name, studentBlock: 'A', studentRoom: '101',
      createdAt: daysAgo(21),
      assignment: {
        cleanerId: cleaners[0]._id, cleanerName: cleaners[0].name,
        assignedAt: minutesAfter(daysAgo(21), 5),
        startedAt: minutesAfter(daysAgo(21), 20),
        completedAt: minutesAfter(daysAgo(21), 45),
      },
    },
    {
      studentId: students[1]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: false, isUrgent: true,
      notes: 'Urgent sweep needed before hostel inspection tomorrow',
      studentName: students[1].name, studentBlock: 'B', studentRoom: '205',
      createdAt: daysAgo(20),
      assignment: {
        cleanerId: cleaners[1]._id, cleanerName: cleaners[1].name,
        assignedAt: minutesAfter(daysAgo(20), 3),
        startedAt: minutesAfter(daysAgo(20), 10),
        completedAt: minutesAfter(daysAgo(20), 25),
      },
    },
    {
      studentId: students[2]._id, status: 'COMPLETED',
      isSweeping: false, isMopping: true, isUrgent: false,
      notes: 'Mopping only please, floor is dusty',
      studentName: students[2].name, studentBlock: 'A', studentRoom: '302',
      createdAt: daysAgo(19),
      assignment: {
        cleanerId: cleaners[0]._id, cleanerName: cleaners[0].name,
        assignedAt: minutesAfter(daysAgo(19), 8),
        startedAt: minutesAfter(daysAgo(19), 15),
        completedAt: minutesAfter(daysAgo(19), 35),
      },
    },
    {
      studentId: students[3]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: true, isUrgent: false,
      notes: 'Full cleaning before weekend',
      studentName: students[3].name, studentBlock: 'C', studentRoom: '410',
      createdAt: daysAgo(18),
      assignment: {
        cleanerId: cleaners[3]._id, cleanerName: cleaners[3].name,
        assignedAt: minutesAfter(daysAgo(18), 4),
        startedAt: minutesAfter(daysAgo(18), 12),
        completedAt: minutesAfter(daysAgo(18), 40),
      },
    },
    {
      studentId: students[4]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: false, isUrgent: false,
      notes: 'Quick sweep please',
      studentName: students[4].name, studentBlock: 'B', studentRoom: '108',
      createdAt: daysAgo(17),
      assignment: {
        cleanerId: cleaners[1]._id, cleanerName: cleaners[1].name,
        assignedAt: minutesAfter(daysAgo(17), 6),
        startedAt: minutesAfter(daysAgo(17), 18),
        completedAt: minutesAfter(daysAgo(17), 30),
      },
    },
    {
      studentId: students[5]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: true, isUrgent: true,
      notes: 'Parents visiting tomorrow, need spotless room',
      studentName: students[5].name, studentBlock: 'D', studentRoom: '215',
      createdAt: daysAgo(16),
      assignment: {
        cleanerId: cleaners[0]._id, cleanerName: cleaners[0].name,
        assignedAt: minutesAfter(daysAgo(16), 2),
        startedAt: minutesAfter(daysAgo(16), 8),
        completedAt: minutesAfter(daysAgo(16), 30),
      },
    },
    {
      studentId: students[6]._id, status: 'COMPLETED',
      isSweeping: false, isMopping: true, isUrgent: false,
      notes: 'Wet mop the bathroom tiles too if possible',
      studentName: students[6].name, studentBlock: 'A', studentRoom: '403',
      createdAt: daysAgo(15),
      assignment: {
        cleanerId: cleaners[3]._id, cleanerName: cleaners[3].name,
        assignedAt: minutesAfter(daysAgo(15), 7),
        startedAt: minutesAfter(daysAgo(15), 22),
        completedAt: minutesAfter(daysAgo(15), 50),
      },
    },
    {
      studentId: students[7]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: false, isUrgent: false,
      studentName: students[7].name, studentBlock: 'C', studentRoom: '312',
      createdAt: daysAgo(14),
      assignment: {
        cleanerId: cleaners[1]._id, cleanerName: cleaners[1].name,
        assignedAt: minutesAfter(daysAgo(14), 9),
        startedAt: minutesAfter(daysAgo(14), 15),
        completedAt: minutesAfter(daysAgo(14), 28),
      },
    },

    // ── Week 2 (14-7 days ago) — 8 requests (6 completed, 2 cancelled) ──
    {
      studentId: students[0]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: true, isUrgent: false,
      notes: 'Regular weekly cleaning',
      studentName: students[0].name, studentBlock: 'A', studentRoom: '101',
      createdAt: daysAgo(12),
      assignment: {
        cleanerId: cleaners[3]._id, cleanerName: cleaners[3].name,
        assignedAt: minutesAfter(daysAgo(12), 3),
        startedAt: minutesAfter(daysAgo(12), 10),
        completedAt: minutesAfter(daysAgo(12), 35),
      },
    },
    {
      studentId: students[8]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: true, isUrgent: false,
      notes: 'Full room cleaning needed',
      studentName: students[8].name, studentBlock: 'D', studentRoom: '102',
      createdAt: daysAgo(11),
      assignment: {
        cleanerId: cleaners[0]._id, cleanerName: cleaners[0].name,
        assignedAt: minutesAfter(daysAgo(11), 5),
        startedAt: minutesAfter(daysAgo(11), 12),
        completedAt: minutesAfter(daysAgo(11), 38),
      },
    },
    {
      studentId: students[9]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: false, isUrgent: true,
      notes: 'Broken glass on floor, urgent sweep needed',
      studentName: students[9].name, studentBlock: 'B', studentRoom: '301',
      createdAt: daysAgo(10),
      assignment: {
        cleanerId: cleaners[1]._id, cleanerName: cleaners[1].name,
        assignedAt: minutesAfter(daysAgo(10), 1),
        startedAt: minutesAfter(daysAgo(10), 5),
        completedAt: minutesAfter(daysAgo(10), 15),
      },
    },
    {
      studentId: students[3]._id, status: 'CANCELLED_ROOM_LOCKED',
      isSweeping: true, isMopping: true, isUrgent: false,
      notes: 'Mopping and sweeping needed',
      studentName: students[3].name, studentBlock: 'C', studentRoom: '410',
      createdAt: daysAgo(9),
      assignment: {
        cleanerId: cleaners[1]._id, cleanerName: cleaners[1].name,
        assignedAt: minutesAfter(daysAgo(9), 4),
        failureReason: 'room_locked',
        completedAt: minutesAfter(daysAgo(9), 20),
      },
    },
    {
      studentId: students[5]._id, status: 'COMPLETED',
      isSweeping: false, isMopping: true, isUrgent: false,
      notes: 'Light mop only',
      studentName: students[5].name, studentBlock: 'D', studentRoom: '215',
      createdAt: daysAgo(8),
      assignment: {
        cleanerId: cleaners[3]._id, cleanerName: cleaners[3].name,
        assignedAt: minutesAfter(daysAgo(8), 6),
        startedAt: minutesAfter(daysAgo(8), 14),
        completedAt: minutesAfter(daysAgo(8), 28),
      },
    },
    {
      studentId: students[6]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: true, isUrgent: true,
      notes: 'Faculty room visit tomorrow, everything must be clean',
      studentName: students[6].name, studentBlock: 'A', studentRoom: '403',
      createdAt: daysAgo(7),
      assignment: {
        cleanerId: cleaners[0]._id, cleanerName: cleaners[0].name,
        assignedAt: minutesAfter(daysAgo(7), 2),
        startedAt: minutesAfter(daysAgo(7), 8),
        completedAt: minutesAfter(daysAgo(7), 32),
      },
    },
    {
      studentId: students[2]._id, status: 'CANCELLED_ROOM_LOCKED',
      isSweeping: true, isMopping: false, isUrgent: false,
      notes: 'Simple sweep',
      studentName: students[2].name, studentBlock: 'A', studentRoom: '302',
      createdAt: daysAgo(7),
      assignment: {
        cleanerId: cleaners[3]._id, cleanerName: cleaners[3].name,
        assignedAt: minutesAfter(daysAgo(7), 10),
        failureReason: 'room_locked',
        completedAt: minutesAfter(daysAgo(7), 25),
      },
    },

    // ── Week 3 (last 7 days) — 9 requests (5 completed, 1 cancelled, 1 assigned, 1 in_progress, 1 open) ──
    {
      studentId: students[1]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: true, isUrgent: false,
      notes: 'Deep clean, please sweep under furniture too',
      studentName: students[1].name, studentBlock: 'B', studentRoom: '205',
      createdAt: daysAgo(5),
      assignment: {
        cleanerId: cleaners[0]._id, cleanerName: cleaners[0].name,
        assignedAt: minutesAfter(daysAgo(5), 4),
        startedAt: minutesAfter(daysAgo(5), 15),
        completedAt: minutesAfter(daysAgo(5), 48),
      },
    },
    {
      studentId: students[4]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: false, isUrgent: false,
      notes: 'Regular sweeping',
      studentName: students[4].name, studentBlock: 'B', studentRoom: '108',
      createdAt: daysAgo(4),
      assignment: {
        cleanerId: cleaners[1]._id, cleanerName: cleaners[1].name,
        assignedAt: minutesAfter(daysAgo(4), 7),
        startedAt: minutesAfter(daysAgo(4), 13),
        completedAt: minutesAfter(daysAgo(4), 25),
      },
    },
    {
      studentId: students[7]._id, status: 'COMPLETED',
      isSweeping: false, isMopping: true, isUrgent: false,
      notes: 'Wet mop please',
      studentName: students[7].name, studentBlock: 'C', studentRoom: '312',
      createdAt: daysAgo(3),
      assignment: {
        cleanerId: cleaners[3]._id, cleanerName: cleaners[3].name,
        assignedAt: minutesAfter(daysAgo(3), 3),
        startedAt: minutesAfter(daysAgo(3), 9),
        completedAt: minutesAfter(daysAgo(3), 22),
      },
    },
    {
      studentId: students[0]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: true, isUrgent: true,
      notes: 'Spilled water everywhere, urgent mopping needed',
      studentName: students[0].name, studentBlock: 'A', studentRoom: '101',
      createdAt: daysAgo(2),
      assignment: {
        cleanerId: cleaners[0]._id, cleanerName: cleaners[0].name,
        assignedAt: minutesAfter(daysAgo(2), 1),
        startedAt: minutesAfter(daysAgo(2), 4),
        completedAt: minutesAfter(daysAgo(2), 15),
      },
    },
    {
      studentId: students[8]._id, status: 'COMPLETED',
      isSweeping: true, isMopping: false, isUrgent: false,
      notes: 'Standard room sweep',
      studentName: students[8].name, studentBlock: 'D', studentRoom: '102',
      createdAt: daysAgo(1),
      assignment: {
        cleanerId: cleaners[1]._id, cleanerName: cleaners[1].name,
        assignedAt: minutesAfter(daysAgo(1), 5),
        startedAt: minutesAfter(daysAgo(1), 11),
        completedAt: minutesAfter(daysAgo(1), 22),
      },
    },
    {
      studentId: students[9]._id, status: 'CANCELLED_ROOM_LOCKED',
      isSweeping: true, isMopping: true, isUrgent: false,
      notes: 'Full cleaning',
      studentName: students[9].name, studentBlock: 'B', studentRoom: '301',
      createdAt: daysAgo(1),
      assignment: {
        cleanerId: cleaners[3]._id, cleanerName: cleaners[3].name,
        assignedAt: minutesAfter(daysAgo(1), 3),
        failureReason: 'room_locked',
        completedAt: minutesAfter(daysAgo(1), 15),
      },
    },
    {
      studentId: students[3]._id, status: 'ASSIGNED',
      isSweeping: true, isMopping: false, isUrgent: false,
      notes: 'Quick sweep before class',
      studentName: students[3].name, studentBlock: 'C', studentRoom: '410',
      createdAt: hoursAfter(daysAgo(0), -2),
      assignment: {
        cleanerId: cleaners[0]._id, cleanerName: cleaners[0].name,
        assignedAt: minutesAfter(hoursAfter(daysAgo(0), -2), 3),
      },
    },
    {
      studentId: students[5]._id, status: 'IN_PROGRESS',
      isSweeping: true, isMopping: true, isUrgent: true,
      notes: 'Urgent! Room needs deep cleaning before event',
      studentName: students[5].name, studentBlock: 'D', studentRoom: '215',
      createdAt: hoursAfter(daysAgo(0), -1),
      assignment: {
        cleanerId: cleaners[1]._id, cleanerName: cleaners[1].name,
        assignedAt: minutesAfter(hoursAfter(daysAgo(0), -1), 2),
        startedAt: minutesAfter(hoursAfter(daysAgo(0), -1), 7),
      },
    },
    {
      studentId: students[6]._id, status: 'OPEN',
      isSweeping: true, isMopping: true, isUrgent: true,
      notes: 'Emergency cleaning request — allergic reaction to dust',
      studentName: students[6].name, studentBlock: 'A', studentRoom: '403',
    },
  ];

  const requests = await Request.create(requestData);
  console.log(`   ✅ Created ${requests.length} requests`);

  // ══════════════════════════════════════════════════════════
  //  FEEDBACK — Varied ratings for histogram distribution
  // ══════════════════════════════════════════════════════════

  const completedRequests = requests.filter((r) => r.status === 'COMPLETED');
  const feedbackData = [
    { requestId: completedRequests[0]._id, studentId: students[0]._id, rating: 5, comment: 'Excellent job! Room is spotless.' },
    { requestId: completedRequests[1]._id, studentId: students[1]._id, rating: 4, comment: 'Good work, very quick response.' },
    { requestId: completedRequests[2]._id, studentId: students[2]._id, rating: 5, comment: 'Perfect mopping, floor is shining!' },
    { requestId: completedRequests[3]._id, studentId: students[3]._id, rating: 3, comment: 'Decent job, missed a corner though.' },
    { requestId: completedRequests[4]._id, studentId: students[4]._id, rating: 4, comment: 'Quick and efficient sweep.' },
    { requestId: completedRequests[5]._id, studentId: students[5]._id, rating: 5, comment: 'Amazing! Room looked brand new.' },
    { requestId: completedRequests[6]._id, studentId: students[6]._id, rating: 4, comment: 'Great mopping, bathroom tiles are clean too.' },
    { requestId: completedRequests[7]._id, studentId: students[7]._id, rating: 3, comment: 'Okay, but left some dust near the window.' },
    { requestId: completedRequests[8]._id, studentId: students[0]._id, rating: 5, comment: 'Consistently excellent cleaning service!' },
    { requestId: completedRequests[9]._id, studentId: students[8]._id, rating: 4, comment: 'Good cleaning work.' },
    { requestId: completedRequests[10]._id, studentId: students[9]._id, rating: 2, comment: 'Could be better. Floor still had marks.' },
    { requestId: completedRequests[11]._id, studentId: students[5]._id, rating: 5, comment: 'Perfect as always!' },
    { requestId: completedRequests[12]._id, studentId: students[6]._id, rating: 4, comment: 'Room looks great before the visit.' },
    { requestId: completedRequests[13]._id, studentId: students[1]._id, rating: 5, comment: 'Thorough deep clean!' },
    { requestId: completedRequests[14]._id, studentId: students[4]._id, rating: 3, comment: 'Average. Took a while to complete.' },
    { requestId: completedRequests[15]._id, studentId: students[7]._id, rating: 5, comment: 'Excellent wet mop job!' },
    { requestId: completedRequests[16]._id, studentId: students[0]._id, rating: 5, comment: 'Lightning fast response, room is perfect!' },
    { requestId: completedRequests[17]._id, studentId: students[8]._id, rating: 4, comment: 'Good standard sweep.' },
  ];

  const feedbacks = await Feedback.create(feedbackData);
  console.log(`   ✅ Created ${feedbacks.length} feedback entries`);

  // ══════════════════════════════════════════════════════════
  //  AUDIT LOGS — Diverse actions across lifecycle
  // ══════════════════════════════════════════════════════════

  const auditData = [];
  for (let i = 0; i < Math.min(completedRequests.length, 10); i++) {
    const req = completedRequests[i];
    const cleaner = cleaners.find(
      (c) => c._id.toString() === req.assignment?.cleanerId?.toString()
    );
    const student = students.find(
      (s) => s._id.toString() === req.studentId?.toString()
    );

    if (!cleaner || !student) continue;

    auditData.push(
      {
        collection: 'requests', documentId: req._id, action: 'CREATE',
        performedBy: student._id, performedByName: student.name,
        summary: `Request created by ${student.name} (${req.studentBlock}-${req.studentRoom})`,
        timestamp: req.createdAt,
      },
      {
        collection: 'requests', documentId: req._id, action: 'UPDATE',
        performedBy: cleaner._id, performedByName: cleaner.name,
        changes: { status: { from: 'OPEN', to: 'ASSIGNED' } },
        summary: `Request accepted by ${cleaner.name}`,
        timestamp: req.assignment?.assignedAt || req.createdAt,
      },
      {
        collection: 'requests', documentId: req._id, action: 'UPDATE',
        performedBy: cleaner._id, performedByName: cleaner.name,
        changes: { status: { from: 'ASSIGNED', to: 'IN_PROGRESS' } },
        summary: `Job started by ${cleaner.name}`,
        timestamp: req.assignment?.startedAt || req.createdAt,
      },
      {
        collection: 'requests', documentId: req._id, action: 'UPDATE',
        performedBy: cleaner._id, performedByName: cleaner.name,
        changes: { status: { from: 'IN_PROGRESS', to: 'COMPLETED' } },
        summary: `Job completed by ${cleaner.name}`,
        timestamp: req.assignment?.completedAt || req.createdAt,
      }
    );
  }

  // Add user creation audit logs
  for (const s of students.slice(0, 3)) {
    auditData.push({
      collection: 'users', documentId: s._id, action: 'CREATE',
      performedBy: s._id, performedByName: s.name,
      summary: `User registered: ${s.name} (${s.role})`,
      timestamp: s.createdAt,
    });
  }

  // Add feedback audit logs
  for (const fb of feedbacks.slice(0, 5)) {
    const student = students.find(
      (s) => s._id.toString() === fb.studentId?.toString()
    );
    if (!student) continue;

    auditData.push({
      collection: 'feedback', documentId: fb._id, action: 'CREATE',
      performedBy: student._id, performedByName: student.name,
      summary: `Feedback submitted: ${fb.rating}/5 stars`,
      timestamp: fb.createdAt,
    });
  }

  const auditLogs = await AuditLog.create(auditData);
  console.log(`   ✅ Created ${auditLogs.length} audit log entries`);

  // ══════════════════════════════════════════════════════════
  //  SUMMARY
  // ══════════════════════════════════════════════════════════

  console.log('\n🎉 Database seeded successfully!');
  console.log('\n── Data Summary ──');
  console.log(`   Students:    ${students.length}`);
  console.log(`   Cleaners:    ${cleaners.length}`);
  console.log(`   Admins:      ${admins.length}`);
  console.log(`   Requests:    ${requests.length}`);
  console.log(`     COMPLETED: ${requests.filter((r) => r.status === 'COMPLETED').length}`);
  console.log(`     CANCELLED: ${requests.filter((r) => r.status === 'CANCELLED_ROOM_LOCKED').length}`);
  console.log(`     OPEN:      ${requests.filter((r) => r.status === 'OPEN').length}`);
  console.log(`     ASSIGNED:  ${requests.filter((r) => r.status === 'ASSIGNED').length}`);
  console.log(`     IN_PROGRESS: ${requests.filter((r) => r.status === 'IN_PROGRESS').length}`);
  console.log(`   Feedback:    ${feedbacks.length}`);
  console.log(`   Audit Logs:  ${auditLogs.length}`);

  console.log('\n── Test Credentials ──');
  console.log('Student:  yuvraj@vit.in / password123');
  console.log('Cleaner:  ravi@cleanit.com / password123');
  console.log('Admin:    admin@cleanit.com / admin123');

  await mongoose.disconnect();
  process.exit(0);
};

seed().catch((err) => {
  console.error('Seed error:', err);
  process.exit(1);
});
