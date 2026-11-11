-- Versioned catalogues, forms, price lists and booking cancellation policies.
CREATE TABLE eogp.config_catalogues (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    scope_kind text NOT NULL CHECK (scope_kind IN ('organization','venue','space','event')),
    scope_venue_id uuid,
    scope_space_id uuid,
    scope_event_id uuid,
    code text NOT NULL,
    name text NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, code),
    CHECK (
      (scope_kind = 'organization' AND num_nonnulls(scope_venue_id, scope_space_id, scope_event_id) = 0)
      OR (scope_kind = 'venue' AND scope_venue_id IS NOT NULL AND scope_space_id IS NULL AND scope_event_id IS NULL)
      OR (scope_kind = 'space' AND scope_venue_id IS NULL AND scope_space_id IS NOT NULL AND scope_event_id IS NULL)
      OR (scope_kind = 'event' AND scope_venue_id IS NULL AND scope_space_id IS NULL AND scope_event_id IS NOT NULL)
    ),
    FOREIGN KEY (organization_id, scope_venue_id) REFERENCES eogp.venues(organization_id, id),
    FOREIGN KEY (organization_id, scope_space_id) REFERENCES eogp.venue_spaces(organization_id, id)
);

CREATE TABLE eogp.config_catalogue_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    catalogue_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','published','retired')),
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, catalogue_id, id),
    UNIQUE (organization_id, catalogue_id, revision_number),
    FOREIGN KEY (organization_id, catalogue_id)
      REFERENCES eogp.config_catalogues(organization_id, id)
);

CREATE TABLE eogp.config_catalogue_options (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    catalogue_id uuid NOT NULL,
    stable_code text NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, catalogue_id, id),
    UNIQUE (organization_id, catalogue_id, stable_code),
    FOREIGN KEY (organization_id, catalogue_id)
      REFERENCES eogp.config_catalogues(organization_id, id)
);

CREATE TABLE eogp.config_catalogue_option_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    catalogue_id uuid NOT NULL,
    option_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    locale text NOT NULL DEFAULT 'bs-BA',
    label text NOT NULL,
    value jsonb NOT NULL DEFAULT 'null'::jsonb,
    state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','published','retired')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, catalogue_id, option_id, id),
    UNIQUE (organization_id, catalogue_id, option_id, revision_number, locale),
    FOREIGN KEY (organization_id, catalogue_id, option_id)
      REFERENCES eogp.config_catalogue_options(organization_id, catalogue_id, id)
);

CREATE TABLE eogp.config_catalogue_revision_options (
    organization_id uuid NOT NULL,
    catalogue_id uuid NOT NULL,
    catalogue_revision_id uuid NOT NULL,
    option_id uuid NOT NULL,
    option_revision_id uuid NOT NULL,
    sort_order integer NOT NULL DEFAULT 0,
    is_default boolean NOT NULL DEFAULT false,
    PRIMARY KEY (organization_id, catalogue_revision_id, option_id),
    FOREIGN KEY (organization_id, catalogue_id, catalogue_revision_id)
      REFERENCES eogp.config_catalogue_revisions(organization_id, catalogue_id, id),
    FOREIGN KEY (organization_id, catalogue_id, option_id, option_revision_id)
      REFERENCES eogp.config_catalogue_option_revisions(organization_id, catalogue_id, option_id, id)
);

CREATE TABLE eogp.booking_form_definitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    scope_kind text NOT NULL DEFAULT 'organization'
      CHECK (scope_kind IN ('organization','venue','space')),
    scope_venue_id uuid,
    scope_space_id uuid,
    form_code text NOT NULL,
    name text NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, form_code),
    CHECK (
      (scope_kind = 'organization' AND scope_venue_id IS NULL AND scope_space_id IS NULL)
      OR (scope_kind = 'venue' AND scope_venue_id IS NOT NULL AND scope_space_id IS NULL)
      OR (scope_kind = 'space' AND scope_venue_id IS NULL AND scope_space_id IS NOT NULL)
    ),
    FOREIGN KEY (organization_id, scope_venue_id) REFERENCES eogp.venues(organization_id, id),
    FOREIGN KEY (organization_id, scope_space_id) REFERENCES eogp.venue_spaces(organization_id, id)
);

CREATE TABLE eogp.booking_form_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    form_definition_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    locale text NOT NULL DEFAULT 'bs-BA',
    field_schema jsonb NOT NULL,
    state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','published','retired')),
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, form_definition_id, id),
    UNIQUE (organization_id, form_definition_id, revision_number, locale),
    FOREIGN KEY (organization_id, form_definition_id)
      REFERENCES eogp.booking_form_definitions(organization_id, id)
);

CREATE TABLE eogp.booking_form_catalogue_bindings (
    organization_id uuid NOT NULL,
    form_revision_id uuid NOT NULL,
    catalogue_id uuid NOT NULL,
    catalogue_revision_id uuid NOT NULL,
    field_code text NOT NULL,
    PRIMARY KEY (organization_id, form_revision_id, field_code),
    FOREIGN KEY (organization_id, form_revision_id)
      REFERENCES eogp.booking_form_revisions(organization_id, id),
    FOREIGN KEY (organization_id, catalogue_id, catalogue_revision_id)
      REFERENCES eogp.config_catalogue_revisions(organization_id, catalogue_id, id)
);

CREATE TABLE eogp.booking_price_lists (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    scope_kind text NOT NULL DEFAULT 'organization' CHECK (scope_kind IN ('organization','venue','space')),
    scope_venue_id uuid,
    scope_space_id uuid,
    code text NOT NULL,
    name text NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, code),
    CHECK (
      (scope_kind = 'organization' AND scope_venue_id IS NULL AND scope_space_id IS NULL)
      OR (scope_kind = 'venue' AND scope_venue_id IS NOT NULL AND scope_space_id IS NULL)
      OR (scope_kind = 'space' AND scope_venue_id IS NULL AND scope_space_id IS NOT NULL)
    ),
    FOREIGN KEY (organization_id, scope_venue_id) REFERENCES eogp.venues(organization_id, id),
    FOREIGN KEY (organization_id, scope_space_id) REFERENCES eogp.venue_spaces(organization_id, id)
);

CREATE TABLE eogp.booking_price_list_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    price_list_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    currency char(3) NOT NULL,
    tax_basis text NOT NULL CHECK (tax_basis IN ('inclusive','exclusive','not_applicable','to_be_confirmed')),
    state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','published','retired')),
    effective_from timestamptz,
    effective_until timestamptz,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, price_list_id, id),
    UNIQUE (organization_id, price_list_id, revision_number),
    FOREIGN KEY (organization_id, price_list_id)
      REFERENCES eogp.booking_price_lists(organization_id, id),
    CHECK (effective_until IS NULL OR effective_from IS NULL OR effective_until > effective_from)
);

CREATE TABLE eogp.booking_price_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    price_list_revision_id uuid NOT NULL,
    item_code text NOT NULL,
    label text NOT NULL,
    unit text NOT NULL DEFAULT 'unit',
    unit_amount numeric(14,2) NOT NULL CHECK (unit_amount >= 0),
    tax_code text,
    quantity_min numeric(12,3) NOT NULL DEFAULT 1 CHECK (quantity_min >= 0),
    quantity_max numeric(12,3) CHECK (quantity_max IS NULL OR quantity_max >= quantity_min),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, price_list_revision_id, item_code),
    FOREIGN KEY (organization_id, price_list_revision_id)
      REFERENCES eogp.booking_price_list_revisions(organization_id, id)
);

CREATE TABLE eogp.cancellation_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    code text NOT NULL,
    name text NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, code)
);

CREATE TABLE eogp.cancellation_policy_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    cancellation_policy_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    customer_mode text NOT NULL CHECK (customer_mode IN ('request_only','approval_required','self_service')),
    approval_rules jsonb NOT NULL DEFAULT '{}'::jsonb,
    commercial_rules jsonb NOT NULL DEFAULT '{}'::jsonb,
    notice_rules jsonb NOT NULL DEFAULT '{}'::jsonb,
    public_terms text NOT NULL,
    state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','published','retired')),
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, cancellation_policy_id, id),
    UNIQUE (organization_id, cancellation_policy_id, revision_number),
    FOREIGN KEY (organization_id, cancellation_policy_id)
      REFERENCES eogp.cancellation_policies(organization_id, id)
);
