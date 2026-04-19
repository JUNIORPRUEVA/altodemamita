ALTER TABLE "sellers"
ALTER COLUMN "sync_id" DROP DEFAULT;

ALTER TABLE "sellers"
ALTER COLUMN "sync_id" TYPE TEXT USING "sync_id"::TEXT;

ALTER TABLE "sellers"
ALTER COLUMN "sync_id" SET DEFAULT gen_random_uuid()::TEXT;
