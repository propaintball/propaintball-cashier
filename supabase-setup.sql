-- ============================================================
-- ProPaintball — Zákaznícky registračný systém
-- Supabase SQL setup
-- Firma: TRESAERIS GROUP s.r.o., IČO: 50925989
-- ============================================================
-- INŠTRUKCIE: Spusti tento súbor v Supabase dashboarde
-- Project → SQL Editor → New query → Paste → Run
-- ============================================================


-- ============================================================
-- 1. TABUĽKA: pb_customers
-- Zákazníci registrovaní cez online formulár alebo pokladňu
-- ============================================================

CREATE TABLE IF NOT EXISTS pb_customers (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    fullname        TEXT        NOT NULL,
    nick            TEXT        UNIQUE NOT NULL,
    email           TEXT        UNIQUE NOT NULL,
    phone           TEXT        NOT NULL,
    lang            TEXT        DEFAULT 'sk',
    consents        JSONB       DEFAULT '{}',
    -- Štruktúra consents:
    -- { "vop": true, "bozp": true, "gdpr": true, "consentedAt": "2026-04-18T12:00:00Z" }
    registered_at   TIMESTAMPTZ DEFAULT NOW(),
    last_seen       TIMESTAMPTZ DEFAULT NOW(),
    tags            TEXT[]      DEFAULT '{}',
    notes           TEXT        DEFAULT '',
    deleted_at      TIMESTAMPTZ DEFAULT NULL
    -- deleted_at IS NULL     → aktívny zákazník
    -- deleted_at IS NOT NULL → soft-deletovaný zákazník (neobjaví sa, kým sa nezaregistruje znova)
);

COMMENT ON TABLE pb_customers IS
    'Zákazníci ProPaintball areálu — registrácia cez web alebo pokladňu. Soft delete cez deleted_at.';

COMMENT ON COLUMN pb_customers.nick IS
    'Unikátna prezývka zákazníka (napr. "SniperMichal"). Povinné pri registrácii.';

COMMENT ON COLUMN pb_customers.consents IS
    'JSONB so súhlasmi: { vop, bozp, gdpr: bool, consentedAt: ISO string }';

COMMENT ON COLUMN pb_customers.deleted_at IS
    'Soft delete — NULL = aktívny. Nastavuje iba service role (admin/pokladňa).';


-- ============================================================
-- 2. TABUĽKA: pb_event_signups
-- Prihlásenia zákazníkov na akcie (Google Calendar eventy)
-- ============================================================

CREATE TABLE IF NOT EXISTS pb_event_signups (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id        TEXT        NOT NULL,
    -- Google Calendar event ID (napr. "7n0k8abc123xyz")
    event_date      TEXT,       -- "2026-04-19"
    event_time      TEXT,       -- "16:00"
    event_arena     TEXT,       -- "RC", "Outdoor", "Small arena"
    event_label     TEXT,       -- "Paintball – RC – 19.4.2026 16:00"
    customer_id     UUID        REFERENCES pb_customers(id) ON DELETE CASCADE,
    signed_up_at    TIMESTAMPTZ DEFAULT NOW(),
    status          TEXT        DEFAULT 'signed_up',
    -- Hodnoty: signed_up | checked_in | no_show
    session_key     TEXT,       -- kľúč session v pokladni, vyplní pokladňa pri importe
    wb_id           TEXT,       -- wristband ID v pokladni, vyplní pokladňa pri check-in

    UNIQUE(event_id, customer_id)
    -- Jeden zákazník sa môže prihlásiť na každú akciu iba raz
);

COMMENT ON TABLE pb_event_signups IS
    'Prihlásenia zákazníkov na akcie z Google Kalendára. Stav sa aktualizuje pri check-in v pokladni.';


-- ============================================================
-- 3. INDEXY
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_pb_event_signups_event_id
    ON pb_event_signups(event_id);

CREATE INDEX IF NOT EXISTS idx_pb_customers_deleted_at
    ON pb_customers(deleted_at)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_pb_customers_email_lower
    ON pb_customers(lower(email));

CREATE INDEX IF NOT EXISTS idx_pb_customers_nick_lower
    ON pb_customers(lower(nick));


-- ============================================================
-- 4. ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE pb_customers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE pb_event_signups  ENABLE ROW LEVEL SECURITY;


-- ============================================================
-- 5. RLS POLITIKY — pb_customers
-- ============================================================

-- INSERT pre anon: registrácia nového zákazníka
CREATE POLICY "anon_insert_customers"
    ON pb_customers FOR INSERT TO anon
    WITH CHECK (deleted_at IS NULL);

-- SELECT pre anon: iba aktívni zákazníci (soft delete filter)
CREATE POLICY "anon_select_active_customers"
    ON pb_customers FOR SELECT TO anon
    USING (deleted_at IS NULL);

-- UPDATE pre anon: ZAKÁZANÉ
CREATE POLICY "anon_no_update_customers"
    ON pb_customers FOR UPDATE TO anon
    USING (false);

-- DELETE pre anon: ZAKÁZANÉ
CREATE POLICY "anon_no_delete_customers"
    ON pb_customers FOR DELETE TO anon
    USING (false);


-- ============================================================
-- 6. RLS POLITIKY — pb_event_signups
-- ============================================================

-- INSERT: zákazník sa môže prihlásiť na akciu
CREATE POLICY "anon_insert_signups"
    ON pb_event_signups FOR INSERT TO anon
    WITH CHECK (true);

-- SELECT: môže čítať (zoznam prihlásených, kontrola duplikátu)
CREATE POLICY "anon_select_signups"
    ON pb_event_signups FOR SELECT TO anon
    USING (true);

-- UPDATE: povolené (zmena statusu pri check-in)
CREATE POLICY "anon_update_signups"
    ON pb_event_signups FOR UPDATE TO anon
    USING (true) WITH CHECK (true);


-- ============================================================
-- 7. FUNKCIA: lookup_customer_by_nick_or_email
-- Vyhľadá zákazníka podľa nicku ALEBO emailu (case insensitive)
-- SECURITY DEFINER = spúšťa sa s právami ownera (service role)
-- Vracia iba: id, nick, fullname — nie email ani telefón
-- ============================================================

CREATE OR REPLACE FUNCTION lookup_customer_by_nick_or_email(
    p_nick  TEXT,
    p_email TEXT
)
RETURNS TABLE (
    id       UUID,
    nick     TEXT,
    fullname TEXT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT
        c.id,
        c.nick,
        c.fullname
    FROM pb_customers c
    WHERE
        c.deleted_at IS NULL
        AND (
            (p_nick  IS NOT NULL AND p_nick  <> '' AND lower(c.nick)  = lower(p_nick))
            OR
            (p_email IS NOT NULL AND p_email <> '' AND lower(c.email) = lower(p_email))
        )
    ORDER BY
        CASE WHEN lower(c.nick) = lower(COALESCE(p_nick,'')) THEN 0 ELSE 1 END,
        c.registered_at DESC
    LIMIT 5;
$$;

-- Udeliť právo anon role (web formulár)
GRANT EXECUTE ON FUNCTION lookup_customer_by_nick_or_email(TEXT, TEXT) TO anon;

COMMENT ON FUNCTION lookup_customer_by_nick_or_email(TEXT, TEXT) IS
    'Vyhľadá aktívnych zákazníkov podľa nicku alebo emailu. Vracia iba id+nick+fullname — bez emailu/telefónu. SECURITY DEFINER pre bypass RLS.';


-- ============================================================
-- 8. FUNKCIA: soft_delete_customer (volá pokladňa/admin)
-- Nastaví deleted_at = NOW(), zákazník zmizne z verejných query
-- ============================================================

CREATE OR REPLACE FUNCTION soft_delete_customer(p_id UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
AS $$
    UPDATE pb_customers
    SET deleted_at = NOW()
    WHERE id = p_id;
$$;

-- Anon NEMÔŽE mazať — iba service role cez cashier
REVOKE EXECUTE ON FUNCTION soft_delete_customer(UUID) FROM anon;

COMMENT ON FUNCTION soft_delete_customer(UUID) IS
    'Soft delete zákazníka — nastaví deleted_at. Volá iba pokladňa/admin cez service role key.';


-- ============================================================
-- 9. FUNKCIA: reactivate_customer (pri opätovnej registrácii)
-- Ak sa zákazník registruje znova s rovnakým emailom/nickom,
-- reaktivuje jeho starý účet namiesto chyby UNIQUE violation
-- ============================================================

CREATE OR REPLACE FUNCTION reactivate_or_create_customer(
    p_fullname TEXT,
    p_nick     TEXT,
    p_email    TEXT,
    p_phone    TEXT,
    p_lang     TEXT,
    p_consents JSONB
)
RETURNS TABLE (id UUID, nick TEXT, is_new BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_existing UUID;
    v_is_new   BOOLEAN := false;
BEGIN
    -- Kontrola existujúceho zákazníka (vrátane soft-deletovaných)
    SELECT c.id INTO v_existing
    FROM pb_customers c
    WHERE lower(c.email) = lower(p_email)
       OR lower(c.nick)  = lower(p_nick)
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
        -- Reaktivovať existujúci účet (aj soft-deletovaný)
        UPDATE pb_customers SET
            fullname     = p_fullname,
            nick         = p_nick,
            phone        = p_phone,
            lang         = p_lang,
            consents     = p_consents,
            last_seen    = NOW(),
            deleted_at   = NULL  -- reaktivácia
        WHERE id = v_existing;
        v_is_new := false;
    ELSE
        -- Vytvoriť nový účet
        INSERT INTO pb_customers (fullname, nick, email, phone, lang, consents)
        VALUES (p_fullname, p_nick, p_email, p_phone, p_lang, p_consents)
        RETURNING pb_customers.id INTO v_existing;
        v_is_new := true;
    END IF;

    RETURN QUERY SELECT v_existing, p_nick, v_is_new;
END;
$$;

GRANT EXECUTE ON FUNCTION reactivate_or_create_customer(TEXT,TEXT,TEXT,TEXT,TEXT,JSONB) TO anon;

COMMENT ON FUNCTION reactivate_or_create_customer(TEXT,TEXT,TEXT,TEXT,TEXT,JSONB) IS
    'Vytvorí nového zákazníka ALEBO reaktivuje soft-deletovaného. Rieši UNIQUE violations pri opätovnej registrácii.';


-- ============================================================
-- KONIEC — po spustení skontroluj:
-- Table Editor → pb_customers (malo by byť 0 riadkov)
-- Table Editor → pb_event_signups (malo by byť 0 riadkov)
-- ============================================================
