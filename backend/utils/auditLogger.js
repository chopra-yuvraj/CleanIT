// ============================================================
//  CleanIT — Audit Logger Utility
// ============================================================
//
//  DBMS Concept: Audit Trail / Change Data Capture
//  Records every significant state change in the system to the
//  audit_logs collection. Combined with TTL indexes, old logs
//  are automatically purged after 90 days.
// ============================================================

const AuditLog = require('../models/AuditLog');

/**
 * Log an action to the audit trail.
 *
 * @param {Object} params
 * @param {string} params.collection - Collection name ('users', 'requests', 'feedback')
 * @param {string} params.documentId - The _id of the affected document
 * @param {string} params.action     - 'CREATE' | 'UPDATE' | 'DELETE'
 * @param {Object} params.performedBy - User who performed the action (or null for system)
 * @param {Object} params.changes    - { field: { from: oldVal, to: newVal } }
 * @param {string} params.summary    - Human-readable description
 */
const logAudit = async ({
  collection,
  documentId,
  action,
  performedBy = null,
  changes = null,
  summary,
}) => {
  try {
    await AuditLog.create({
      collection,
      documentId,
      action,
      performedBy: performedBy?._id || performedBy,
      performedByName: performedBy?.name || 'system',
      changes,
      summary,
    });
  } catch (error) {
    // Audit logging should never break the main flow
    console.error('Audit log write failed:', error.message);
  }
};

module.exports = { logAudit };
