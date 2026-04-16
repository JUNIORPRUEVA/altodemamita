CREATE TABLE IF NOT EXISTS "company_profiles" (
  "id" UUID PRIMARY KEY,
  "name" TEXT NOT NULL,
  "phone" TEXT NULL,
  "address" TEXT NULL,
  "logo_base64" TEXT NULL,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);