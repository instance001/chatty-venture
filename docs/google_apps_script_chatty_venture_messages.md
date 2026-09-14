# Chatty-Venture publisher messages

The existing Chatty-Mini web app deliberately rejects Chatty-Venture payloads.
Keep its existing report handler, then add the following branch to the same Apps
Script project and deploy a new web-app version. This keeps both apps in one
publisher mailbox while retaining exact package validation.

## 1. Add these constants near the existing constants

```javascript
const VENTURE_APP_NAME = 'Chatty-Venture';
const VENTURE_PACKAGE_ID = 'io.instance001.chatty_venture';
const VENTURE_MESSAGE_KEYS = ['subject', 'body'];
const VENTURE_MAX_SUBJECT_CHARS = 160;
const VENTURE_MAX_BODY_CHARS = 2000;
```

## 2. Add this before `const validation = validatePayload(payload);` in `doPost`

```javascript
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
```

## 3. Add these helper functions

```javascript
function validateVentureMessage(payload) {
  const rootKeys = ['schemaVersion', 'messageId', 'timestamp', 'app', 'message'];
  const appKeys = ['name', 'packageId', 'version'];
  if (!isPlainObject(payload) || !hasOnlyApprovedKeys(payload, rootKeys)) return fail('unknown_root_field');
  if (payload.schemaVersion !== 1) return fail('unsupported_schema_version');
  if (!isSafeString(payload.messageId, 12, 96) || !/^msg_[A-Za-z0-9_-]+$/.test(payload.messageId)) return fail('invalid_message_id');
  if (!isSafeString(payload.timestamp, 10, 64) || isNaN(Date.parse(payload.timestamp))) return fail('invalid_timestamp');
  if (!isPlainObject(payload.app) || !hasOnlyApprovedKeys(payload.app, appKeys)) return fail('invalid_app');
  if (payload.app.name !== VENTURE_APP_NAME || payload.app.packageId !== VENTURE_PACKAGE_ID) return fail('invalid_app');
  if (!isSafeString(payload.app.version, 1, MAX_LABEL_CHARS)) return fail('invalid_app_version');
  if (!isPlainObject(payload.message) || !hasOnlyApprovedKeys(payload.message, VENTURE_MESSAGE_KEYS)) return fail('invalid_message');
  if (!isSafeString(payload.message.subject, 1, VENTURE_MAX_SUBJECT_CHARS)) return fail('invalid_subject');
  if (!isSafeString(payload.message.body, 1, VENTURE_MAX_BODY_CHARS)) return fail('invalid_body');
  return { ok: true };
}

function buildVentureMessageEmail(payload) {
  return [
    'Chatty-Venture publisher message', '',
    `Message ID: ${payload.messageId}`,
    `Timestamp: ${payload.timestamp}`,
    `App version: ${payload.app.version}`, '',
    'Message', payload.message.body, '',
    'Privacy boundary',
    'Only content intentionally entered in the in-app Message developer form was sent.'
  ].join('\n');
}
```

Deploy the updated web app as the existing public endpoint. The Chatty-Venture
client is already configured for that deployment URL. Do not rotate the URL
unless you also update `DeveloperMessageService`.
