CREATE TABLE "authorized_devices" (
  "id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "company_profile_id" UUID,
  "device_id" TEXT NOT NULL,
  "device_name" TEXT,
  "platform" TEXT,
  "is_primary" BOOLEAN NOT NULL DEFAULT false,
  "can_write" BOOLEAN NOT NULL DEFAULT false,
  "last_seen_at" TIMESTAMP(3),
  "revoked_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "authorized_devices_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "authorized_devices_user_id_device_id_key"
ON "authorized_devices"("user_id", "device_id");

CREATE INDEX "authorized_devices_user_id_revoked_at_is_primary_can_write_idx"
ON "authorized_devices"("user_id", "revoked_at", "is_primary", "can_write");

CREATE INDEX "authorized_devices_device_id_idx"
ON "authorized_devices"("device_id");

ALTER TABLE "authorized_devices"
ADD CONSTRAINT "authorized_devices_user_id_fkey"
FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "authorized_devices"
ADD CONSTRAINT "authorized_devices_company_profile_id_fkey"
FOREIGN KEY ("company_profile_id") REFERENCES "company_profiles"("id") ON DELETE SET NULL ON UPDATE CASCADE;