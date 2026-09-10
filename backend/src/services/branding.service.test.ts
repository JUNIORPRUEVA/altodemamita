import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  BRANDING_DIR_ENV,
  BRANDING_LOGO_FILENAME,
  BrandingValidationError,
  brandingDir,
  brandingLogoMetadata,
  brandingLogoPath,
  decodeBrandingBase64,
  detectImageType,
  readBrandingLogo,
  saveBrandingLogo,
} from "./branding.service";

/** PNG valido minimo (1x1) usado como archivo de prueba. */
const PNG_1X1 = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);
const JPEG_HEADER = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46]);

function withTempBrandingDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "branding-test-"));
  process.env[BRANDING_DIR_ENV] = dir;
  return dir;
}

function cleanup(dir: string) {
  delete process.env[BRANDING_DIR_ENV];
  fs.rmSync(dir, { recursive: true, force: true });
}

test("detecta PNG y JPG por firma binaria", () => {
  assert.deepEqual(detectImageType(PNG_1X1), {
    extension: "png",
    contentType: "image/png",
  });
  assert.deepEqual(detectImageType(JPEG_HEADER), {
    extension: "jpg",
    contentType: "image/jpeg",
  });
  assert.equal(detectImageType(Buffer.from("no soy una imagen")), null);
  assert.equal(detectImageType(Buffer.alloc(0)), null);
});

test("usa una unica ruta canonica configurable por entorno", () => {
  const original = process.env[BRANDING_DIR_ENV];
  try {
    delete process.env[BRANDING_DIR_ENV];
    assert.equal(brandingDir(), "/app/storage/branding");
    process.env[BRANDING_DIR_ENV] = "/app/storage/branding-acceptance";
    assert.equal(brandingDir(), "/app/storage/branding-acceptance");

    // Comparacion agnostica del sistema de archivos (en Linux la ruta es
    // literalmente /app/storage/branding-acceptance/logo.png).
    const resolved = brandingLogoPath();
    assert.equal(path.basename(resolved), "logo.png");
    assert.equal(path.dirname(resolved), path.resolve("/app/storage/branding-acceptance"));
  } finally {
    if (original === undefined) {
      delete process.env[BRANDING_DIR_ENV];
    } else {
      process.env[BRANDING_DIR_ENV] = original;
    }
  }
});

test("el nombre del archivo es fijo y no permite directory traversal", () => {
  const dir = withTempBrandingDir();
  try {
    for (const hostile of [
      "../../etc/passwd",
      "..\\..\\windows\\system32\\config",
      "/etc/shadow",
      "sub/dir/logo.png",
    ]) {
      const resolved = brandingLogoPath(hostile);
      assert.equal(path.dirname(resolved), path.resolve(dir));
      assert.equal(path.basename(resolved), path.basename(hostile));
    }
    assert.equal(brandingLogoPath(), path.join(dir, BRANDING_LOGO_FILENAME));
  } finally {
    cleanup(dir);
  }
});

test("lee null cuando el volumen existe pero no hay logo publicado", async () => {
  const dir = withTempBrandingDir();
  try {
    assert.equal(await readBrandingLogo(), null);
    const metadata = await brandingLogoMetadata();
    assert.equal(metadata.present, false);
    assert.equal(metadata.sha256, null);
    assert.equal(metadata.size, 0);
  } finally {
    cleanup(dir);
  }
});

test("guarda el logo con nombre canonico y SHA256 estable", async () => {
  const dir = withTempBrandingDir();
  try {
    const saved = await saveBrandingLogo({
      bytes: PNG_1X1,
      originalFilename: "EL ALTO DONA MAMITA logo final.png",
    });

    assert.equal(saved.filename, "logo.png");
    assert.equal(saved.contentType, "image/png");
    assert.equal(saved.size, PNG_1X1.length);
    assert.equal(
      saved.sha256,
      crypto.createHash("sha256").update(PNG_1X1).digest("hex"),
    );

    const onDisk = fs.readFileSync(path.join(dir, "logo.png"));
    assert.equal(onDisk.equals(PNG_1X1), true);

    const reread = await readBrandingLogo();
    assert.equal(reread?.sha256, saved.sha256);

    const metadata = await brandingLogoMetadata();
    assert.equal(metadata.present, true);
    assert.equal(metadata.sha256, saved.sha256);

    // Conserva el original sin transformar y documenta los metadatos.
    assert.equal(
      fs.readFileSync(path.join(dir, "logo-original.png")).equals(PNG_1X1),
      true,
    );
    const metadataFile = JSON.parse(
      fs.readFileSync(path.join(dir, "metadata.json"), "utf8"),
    );
    assert.equal(metadataFile.sha256, saved.sha256);
    assert.equal(metadataFile.size, PNG_1X1.length);
    assert.equal(metadataFile.canonicalFilename, "logo.png");
    assert.equal(
      metadataFile.originalFilename,
      "EL ALTO DONA MAMITA logo final.png",
    );
  } finally {
    cleanup(dir);
  }
});

test("conserva solo el respaldo anterior mas reciente", async () => {
  const dir = withTempBrandingDir();
  try {
    await saveBrandingLogo({ bytes: PNG_1X1 });
    await saveBrandingLogo({ bytes: PNG_1X1 });
    await saveBrandingLogo({ bytes: PNG_1X1 });

    const backups = fs
      .readdirSync(dir)
      .filter((name) => name.startsWith("logo.previous."));
    assert.equal(backups.length, 1);
    assert.equal(fs.existsSync(path.join(dir, "logo.png")), true);
  } finally {
    cleanup(dir);
  }
});

test("no deja archivos temporales tras un guardado correcto", async () => {
  const dir = withTempBrandingDir();
  try {
    await saveBrandingLogo({ bytes: PNG_1X1 });
    const temps = fs.readdirSync(dir).filter((name) => name.startsWith(".tmp-"));
    assert.deepEqual(temps, []);
  } finally {
    cleanup(dir);
  }
});

test("rechaza archivos vacios, no-imagen y sobredimensionados", async () => {
  const dir = withTempBrandingDir();
  try {
    await assert.rejects(
      () => saveBrandingLogo({ bytes: Buffer.alloc(0) }),
      (error: unknown) =>
        error instanceof BrandingValidationError && error.code === "EMPTY_FILE",
    );

    await assert.rejects(
      () => saveBrandingLogo({ bytes: Buffer.from("texto plano") }),
      (error: unknown) =>
        error instanceof BrandingValidationError && error.code === "INVALID_IMAGE",
    );

    await assert.rejects(
      () => saveBrandingLogo({ bytes: Buffer.concat([PNG_1X1, Buffer.alloc(6 * 1024 * 1024)]) }),
      (error: unknown) =>
        error instanceof BrandingValidationError && error.code === "FILE_TOO_LARGE",
    );

    // Un rechazo nunca debe dejar un logo publicado.
    assert.equal(fs.existsSync(path.join(dir, "logo.png")), false);
  } finally {
    cleanup(dir);
  }
});

test("decodifica base64 incluyendo data URL y produce el mismo SHA256", async () => {
  const dir = withTempBrandingDir();
  try {
    const plain = decodeBrandingBase64(PNG_1X1.toString("base64"));
    const dataUrl = decodeBrandingBase64(
      `data:image/png;base64,${PNG_1X1.toString("base64")}`,
    );

    assert.equal(plain.equals(PNG_1X1), true);
    assert.equal(dataUrl.equals(PNG_1X1), true);

    assert.throws(
      () => decodeBrandingBase64("   "),
      (error: unknown) =>
        error instanceof BrandingValidationError && error.code === "EMPTY_FILE",
    );
  } finally {
    cleanup(dir);
  }
});
