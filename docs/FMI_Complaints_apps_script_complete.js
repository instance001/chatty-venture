/**
 * FMI receiver for Chatty-mini AI-content reports and Chatty-Venture
 * publisher messages.
 *
 * It emails accepted, explicitly submitted payloads and stores no reports.
 * Deploy this file as the existing Apps Script web app.
 */

const RECIPIENT_EMAIL = 'fractalinfrastructuremedia@gmail.com';

// Chatty-mini AI report contract.
const APP_NAME = 'Chatty-mini';
const PACKAGE_ID = 'io.instance001.chatmini';
const SCHEMA_VERSION = 1;

const MAX_REQUEST_CHARS = 20000;
const MAX_ASSISTANT_RESPONSE_CHARS = 12000;
const MAX_PRECEDING_PROMPT_CHARS = 4000;
const MAX_NOTE_CHARS = 2000;
const MAX_LABEL_CHARS = 160;

const ROOT_KEYS = [
  'schemaVersion',
  'reportId',
  'timestamp',
  'app',
  'generation',
  'report',
  'content'
];
const APP_KEYS = ['name', 'packageId', 'version'];
const GENERATION_KEYS = ['lane', 'providerLabel', 'modelLabel'];
const REPORT_KEYS = ['reason', 'note'];
const CONTENT_KEYS = ['assistantResponse', 'precedingUserPrompt'];
const ALLOWED_REASONS = [
  'offensive',
  'hate_or_harassment',
  'sexual_content',
  'violence_or_self_harm',
  'illegal_or_dangerous',
  'deceptive_or_impersonation',
  'privacy_or_credentials',
  'other'
];
const ALLOWED_LANES = ['local', 'cloud'];

// Chatty-Venture publisher-message contract.
const VENTURE_APP_NAME = 'Chatty-Venture';
const VENTURE_PACKAGE_ID = 'io.instance001.chatty_venture';
const VENTURE_MESSAGE_KEYS = ['subject', 'body'];
const VENTURE_MAX_SUBJECT_CHARS = 160;
const VENTURE_MAX_BODY_CHARS = 2000;

function doGet() {
  return jsonResponse({
    ok: true,
    service: 'fmi-chatty-receiver',
    status: 'healthy'
  });
}

function doPost(e) {
  try {
    const rawBody = getRawBody(e);
    if (!rawBody) return jsonResponse({ ok: false, error: 'empty_request' });
    if (rawBody.length > MAX_REQUEST_CHARS) {
      return jsonResponse({ ok: false, error: 'request_too_large' });
    }

    let payload;
    try {
      payload = JSON.parse(rawBody);
    } catch (err) {
      return jsonResponse({ ok: false, error: 'invalid_json' });
    }

    // Chatty-Venture messages use their own deliberately small schema.
    if (payload && payload.app && payload.app.name === VENTURE_APP_NAME) {
      const validation = validateVentureMessage(payload);
      if (!validation.ok) return jsonResponse({ ok: false, error: validation.error });

      MailApp.sendEmail({
        to: RECIPIENT_EMAIL,
        subject: `[Chatty-Venture message] ${payload.message.subject}`,
        body: buildVentureMessageEmail(payload),
        name: 'Chatty-Venture publisher messages'
      });
      return jsonResponse({ ok: true, messageId: payload.messageId });
    }

    // Original Chatty-mini report path.
    const validation = validatePayload(payload);
    if (!validation.ok) return jsonResponse({ ok: false, error: validation.error });

    MailApp.sendEmail({
      to: RECIPIENT_EMAIL,
      subject: `[Chatty-mini AI report] ${payload.report.reason} — ${payload.reportId}`,
      body: buildEmailBody(payload),
      name: 'FMI AI Content Reports'
    });
    return jsonResponse({ ok: true, reportId: payload.reportId });
  } catch (err) {
    return jsonResponse({ ok: false, error: 'server_error' });
  }
}

function getRawBody(e) {
  if (!e || !e.postData || typeof e.postData.contents !== 'string') return '';
  return e.postData.contents;
}

function validatePayload(payload) {
  if (!isPlainObject(payload)) return fail('payload_must_be_object');
  if (!hasOnlyApprovedKeys(payload, ROOT_KEYS)) return fail('unknown_root_field');
  if (payload.schemaVersion !== SCHEMA_VERSION) return fail('unsupported_schema_version');
  if (!isSafeString(payload.reportId, 12, 96) || !/^rpt_[A-Za-z0-9_-]+$/.test(payload.reportId)) return fail('invalid_report_id');
  if (!isSafeString(payload.timestamp, 10, 64) || isNaN(Date.parse(payload.timestamp))) return fail('invalid_timestamp');

  if (!isPlainObject(payload.app) || !hasOnlyApprovedKeys(payload.app, APP_KEYS)) return fail('invalid_app');
  if (payload.app.name !== APP_NAME) return fail('invalid_app_name');
  if (payload.app.packageId !== PACKAGE_ID) return fail('invalid_package_id');
  if (!isSafeString(payload.app.version, 1, MAX_LABEL_CHARS)) return fail('invalid_app_version');

  if (!isPlainObject(payload.generation) || !hasOnlyApprovedKeys(payload.generation, GENERATION_KEYS)) return fail('invalid_generation');
  if (!ALLOWED_LANES.includes(payload.generation.lane)) return fail('invalid_lane');
  if (!isSafeString(payload.generation.providerLabel, 1, MAX_LABEL_CHARS)) return fail('invalid_provider_label');
  if (!isSafeString(payload.generation.modelLabel, 1, MAX_LABEL_CHARS)) return fail('invalid_model_label');

  if (!isPlainObject(payload.report) || !hasOnlyApprovedKeys(payload.report, REPORT_KEYS)) return fail('invalid_report');
  if (!ALLOWED_REASONS.includes(payload.report.reason)) return fail('invalid_reason');
  if (payload.report.note !== null && payload.report.note !== undefined && !isSafeString(payload.report.note, 0, MAX_NOTE_CHARS)) return fail('invalid_note');

  if (!isPlainObject(payload.content) || !hasOnlyApprovedKeys(payload.content, CONTENT_KEYS)) return fail('invalid_content');
  if (!isSafeString(payload.content.assistantResponse, 1, MAX_ASSISTANT_RESPONSE_CHARS)) return fail('invalid_assistant_response');
  if (payload.content.precedingUserPrompt !== null && payload.content.precedingUserPrompt !== undefined && !isSafeString(payload.content.precedingUserPrompt, 0, MAX_PRECEDING_PROMPT_CHARS)) return fail('invalid_preceding_user_prompt');

  return { ok: true };
}

function validateVentureMessage(payload) {
  const rootKeys = ['schemaVersion', 'messageId', 'timestamp', 'app', 'message'];
  if (!isPlainObject(payload) || !hasOnlyApprovedKeys(payload, rootKeys)) return fail('unknown_root_field');
  if (payload.schemaVersion !== 1) return fail('unsupported_schema_version');
  if (!isSafeString(payload.messageId, 12, 96) || !/^msg_[A-Za-z0-9_-]+$/.test(payload.messageId)) return fail('invalid_message_id');
  if (!isSafeString(payload.timestamp, 10, 64) || isNaN(Date.parse(payload.timestamp))) return fail('invalid_timestamp');

  if (!isPlainObject(payload.app) || !hasOnlyApprovedKeys(payload.app, APP_KEYS)) return fail('invalid_app');
  if (payload.app.name !== VENTURE_APP_NAME || payload.app.packageId !== VENTURE_PACKAGE_ID) return fail('invalid_app');
  if (!isSafeString(payload.app.version, 1, MAX_LABEL_CHARS)) return fail('invalid_app_version');

  if (!isPlainObject(payload.message) || !hasOnlyApprovedKeys(payload.message, VENTURE_MESSAGE_KEYS)) return fail('invalid_message');
  if (!isSafeString(payload.message.subject, 1, VENTURE_MAX_SUBJECT_CHARS)) return fail('invalid_subject');
  if (!isSafeString(payload.message.body, 1, VENTURE_MAX_BODY_CHARS)) return fail('invalid_body');
  return { ok: true };
}

function buildEmailBody(payload) {
  const precedingPrompt = payload.content.precedingUserPrompt ? payload.content.precedingUserPrompt : '[not included]';
  const note = payload.report.note ? payload.report.note : '[none]';
  return [
    'Chatty-mini AI content report', '',
    `Report ID: ${payload.reportId}`,
    `Timestamp: ${payload.timestamp}`,
    `Reason: ${payload.report.reason}`, '',
    'App',
    `Name: ${payload.app.name}`,
    `Package ID: ${payload.app.packageId}`,
    `Version: ${payload.app.version}`, '',
    'Generation',
    `Lane: ${payload.generation.lane}`,
    `Provider/model source: ${payload.generation.providerLabel}`,
    `Model label: ${payload.generation.modelLabel}`, '',
    'Optional user note', note, '',
    'Immediately preceding user prompt', precedingPrompt, '',
    'Reported assistant response', payload.content.assistantResponse, '',
    'Privacy boundary',
    'This report was explicitly submitted from inside Chatty-mini. Normal chats are not routed through Fractal Media Infrastructure.'
  ].join('\n');
}

function buildVentureMessageEmail(payload) {
  return [
    'Chatty-Venture publisher message', '',
    `Message ID: ${payload.messageId}`,
    `Timestamp: ${payload.timestamp}`,
    `App version: ${payload.app.version}`, '',
    'Message',
    payload.message.body, '',
    'Privacy boundary',
    'Only content intentionally entered in the in-app Message developer form was sent.'
  ].join('\n');
}

function jsonResponse(body) {
  return ContentService.createTextOutput(JSON.stringify(body)).setMimeType(ContentService.MimeType.JSON);
}

function hasOnlyApprovedKeys(value, approvedKeys) {
  const keys = Object.keys(value);
  for (let i = 0; i < keys.length; i += 1) {
    if (!approvedKeys.includes(keys[i])) return false;
  }
  return true;
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isSafeString(value, minLength, maxLength) {
  return typeof value === 'string' && value.length >= minLength && value.length <= maxLength;
}

function fail(error) {
  return { ok: false, error: error };
}
