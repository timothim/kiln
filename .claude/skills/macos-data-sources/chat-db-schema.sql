-- chat-db-schema.sql
-- Reference queries for Kiln's Messages ingest (chat.db).
-- See macos-data-sources/SKILL.md §2 for context and permission model.
--
-- DO NOT open the live database at ~/Library/Messages/chat.db.
-- Copy chat.db, chat.db-shm, chat.db-wal to a temp directory and open the
-- copy read-only (SQLITE_OPEN_READONLY). The live file is WAL-locked by
-- Messages.app; attempting to read it directly corrupts the WAL on some
-- macOS versions.

-- ----------------------------------------------------------------------
-- Schema subset (reference only; do not CREATE from this).
-- ----------------------------------------------------------------------
--
-- message
--   rowid                     INTEGER PRIMARY KEY
--   guid                      TEXT    -- stable id across iCloud sync
--   text                      TEXT    -- plain body; NULL for modern rows
--   attributedBody            BLOB    -- NSKeyedArchiver payload
--   handle_id                 INTEGER -- FK -> handle.rowid
--   is_from_me                INTEGER -- 0 or 1
--   date                      INTEGER -- Mac absolute time, ns since 2001-01-01 UTC
--   service                   TEXT    -- 'iMessage' or 'SMS'
--   expressive_send_style_id  TEXT    -- non-NULL => message effect (filter out)
--
-- chat
--   rowid             INTEGER PRIMARY KEY
--   chat_identifier   TEXT    -- phone, email, or chatXXXX
--   display_name      TEXT
--
-- chat_message_join (many-to-many)
--   chat_id           INTEGER
--   message_id        INTEGER
--
-- handle
--   rowid             INTEGER PRIMARY KEY
--   id                TEXT    -- phone or email
--   service           TEXT

-- ----------------------------------------------------------------------
-- Q1. Canonical user-voice extraction.
-- Requires the registered SQLite UDF `kiln_extract_attributedbody(BLOB)->TEXT`
-- from permissions-patterns.swift §4. Without it, strip the COALESCE and
-- expect ~30% of recent rows to come back with empty body.
-- ----------------------------------------------------------------------

SELECT
  m.rowid                                                              AS rowid,
  m.guid                                                               AS guid,
  COALESCE(
    m.text,
    kiln_extract_attributedbody(m.attributedBody)
  )                                                                    AS body,
  m.date / 1000000000 + strftime('%s', '2001-01-01')                    AS unix_ts,
  c.chat_identifier                                                    AS chat_identifier,
  c.display_name                                                       AS display_name,
  m.service                                                            AS service
FROM message m
JOIN chat_message_join cmj ON cmj.message_id = m.rowid
JOIN chat c                ON c.rowid       = cmj.chat_id
WHERE m.is_from_me = 1
  AND COALESCE(m.text, m.attributedBody) IS NOT NULL
  AND length(COALESCE(m.text, '')) > 0
  -- Reactions (auto-generated tapbacks)
  AND (m.text IS NULL OR (
        m.text NOT LIKE 'Liked "%'
    AND m.text NOT LIKE 'Loved "%'
    AND m.text NOT LIKE 'Laughed at "%'
    AND m.text NOT LIKE 'Emphasized "%'
    AND m.text NOT LIKE 'Questioned "%'
    AND m.text NOT LIKE 'Disliked "%'
    AND m.text NOT LIKE 'Removed a % reaction %'
  ))
  -- Short message-effect echoes
  AND NOT (m.expressive_send_style_id IS NOT NULL AND length(COALESCE(m.text, '')) < 20)
  -- Length filters per SPEC §1.2
  AND length(COALESCE(m.text, 'x')) >= 6
  AND length(COALESCE(m.text, 'x')) <= 4000
  -- Pre-2001 corruption guard (978307200 = 2001-01-01 UTC)
  AND (m.date / 1000000000 + strftime('%s', '2001-01-01')) >= 978307200
ORDER BY m.date ASC;

-- ----------------------------------------------------------------------
-- Q2. Per-chat outbound counts — diagnostic for the Dataset Doctor.
-- "You have 14 chats with >100 outbound messages."
-- ----------------------------------------------------------------------

SELECT
  c.chat_identifier,
  c.display_name,
  COUNT(*)                                                  AS outbound_count,
  MIN(m.date / 1000000000 + strftime('%s', '2001-01-01'))    AS first_unix_ts,
  MAX(m.date / 1000000000 + strftime('%s', '2001-01-01'))    AS last_unix_ts
FROM message m
JOIN chat_message_join cmj ON cmj.message_id = m.rowid
JOIN chat c                ON c.rowid       = cmj.chat_id
WHERE m.is_from_me = 1
  AND COALESCE(m.text, m.attributedBody) IS NOT NULL
GROUP BY c.rowid
HAVING outbound_count > 0
ORDER BY outbound_count DESC;

-- ----------------------------------------------------------------------
-- Q3. Schema probe — run once after copy to validate schema version.
-- If any of these return 0, the schema has drifted; refuse to ingest and
-- show a "Supported macOS version" message.
-- ----------------------------------------------------------------------

SELECT COUNT(*) FROM sqlite_master       WHERE type = 'table' AND name = 'message';
SELECT COUNT(*) FROM pragma_table_info('message') WHERE name = 'attributedBody';
SELECT COUNT(*) FROM pragma_table_info('message') WHERE name = 'is_from_me';
SELECT COUNT(*) FROM pragma_table_info('message') WHERE name = 'expressive_send_style_id';
SELECT COUNT(*) FROM pragma_table_info('message') WHERE name = 'guid';

-- ----------------------------------------------------------------------
-- Q4. Row-count sanity checks — log these; don't gate on them.
-- ----------------------------------------------------------------------

SELECT COUNT(*)                    AS total_messages FROM message;
SELECT COUNT(*)                    AS outbound       FROM message WHERE is_from_me = 1;
SELECT COUNT(DISTINCT c.rowid)     AS chats          FROM chat c;
SELECT COUNT(DISTINCT m.handle_id) AS handles        FROM message m;

-- ----------------------------------------------------------------------
-- Q5. Incremental ingest — use guid, not rowid.
-- `since_guid` is the last guid we successfully imported.
-- ----------------------------------------------------------------------

SELECT m.guid, m.text, m.date
FROM message m
WHERE m.is_from_me = 1
  AND m.rowid > (SELECT rowid FROM message WHERE guid = :since_guid)
ORDER BY m.date ASC;
