import crypto from "node:crypto";
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";

/**
 * Almacenamiento persistente de branding institucional.
 *
 * El logo vive en un VOLUMEN montado en el backend, nunca en la capa de la
 * imagen Docker ni dentro de PostgreSQL. La ruta es configurable por entorno
 * para poder aislar acceptance y produccion:
 *
 *   BRANDING_STORAGE_PATH=/app/storage/branding
 */

export const BRANDING_DIR_ENV = "BRANDING_STORAGE_PATH";
export const DEFAULT_BRANDING_DIR = "/app/storage/branding";

/** Nombre canonico: el consumidor nunca depende del nombre original. */
export const BRANDING_LOGO_FILENAME = "logo.png";
/** Copia sin transformar del original suministrado por el operador. */
export const BRANDING_ORIGINAL_FILENAME = "logo-original.png";
/** Metadatos de verificacion (tamano, sha256, contenido). */
export const BRANDING_METADATA_FILENAME = "metadata.json";

export const MAX_BRANDING_LOGO_BYTES = 5 * 1024 * 1024;

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

export type BrandingLogo = {
  bytes: Buffer;
  contentType: string;
  extension: "png" | "jpg";
  size: number;
  sha256: string;
  updatedAt: Date;
  filename: string;
};

export class BrandingValidationError extends Error {
  constructor(
    message: string,
    readonly code: string,
  ) {
    super(message);
    this.name = "BrandingValidationError";
  }
}

/** Directorio de branding efectivo (una unica ruta canonica). */
export function brandingDir(): string {
  const configured = process.env[BRANDING_DIR_ENV]?.trim();
  return configured && configured.length > 0 ? configured : DEFAULT_BRANDING_DIR;
}

/**
 * Ruta del logo canonico.
 *
 * El nombre es FIJO: ninguna entrada del usuario participa en la resolucion,
 * por lo que no existe superficie para directory traversal.
 */
export function brandingLogoPath(filename: string = BRANDING_LOGO_FILENAME): string {
  const dir = brandingDir();
  const safe = path.basename(filename);
  const resolved = path.resolve(dir, safe);
  if (path.dirname(resolved) !== path.resolve(dir)) {
    throw new BrandingValidationError("Ruta de branding invalida.", "INVALID_PATH");
  }
  return resolved;
}

export function detectImageType(
  bytes: Buffer,
): { extension: "png" | "jpg"; contentType: string } | null {
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(PNG_MAGIC)) {
    return { extension: "png", contentType: "image/png" };
  }
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return { extension: "jpg", contentType: "image/jpeg" };
  }
  return null;
}

export async function ensureBrandingDir(): Promise<string> {
  const dir = brandingDir();
  await fsp.mkdir(dir, { recursive: true });
  return dir;
}

function toLogo(bytes: Buffer, filename: string, updatedAt: Date): BrandingLogo {
  const detected = detectImageType(bytes);
  return {
    bytes,
    contentType: detected?.contentType ?? "application/octet-stream",
    extension: detected?.extension ?? "png",
    size: bytes.length,
    sha256: crypto.createHash("sha256").update(bytes).digest("hex"),
    updatedAt,
    filename,
  };
}

/**
 * Lee el logo persistente.
 *
 * Devuelve `null` cuando el volumen esta montado pero todavia no hay logo:
 * el consumidor debe degradar con su propio fallback, nunca fallar.
 */
export async function readBrandingLogo(): Promise<BrandingLogo | null> {
  const filePath = brandingLogoPath();
  try {
    const [bytes, stat] = await Promise.all([fsp.readFile(filePath), fsp.stat(filePath)]);
    if (bytes.length === 0) {
      return null;
    }
    return toLogo(bytes, BRANDING_LOGO_FILENAME, stat.mtime);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return null;
    }
    throw error;
  }
}

export async function brandingLogoMetadata() {
  const dir = brandingDir();
  const logo = await readBrandingLogo();
  return {
    directory: dir,
    configured: Boolean(process.env[BRANDING_DIR_ENV]?.trim()),
    present: logo !== null,
    filename: logo?.filename ?? null,
    size: logo?.size ?? 0,
    sha256: logo?.sha256 ?? null,
    contentType: logo?.contentType ?? null,
    updatedAt: logo?.updatedAt?.toISOString() ?? null,
  };
}

/** Conserva el logo anterior sin acumular versiones. */
async function backupPreviousLogo(dir: string): Promise<void> {
  const current = path.join(dir, BRANDING_LOGO_FILENAME);
  if (!fs.existsSync(current)) {
    return;
  }
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backup = path.join(dir, `logo.previous.${stamp}.png`);
  await fsp.rename(current, backup);

  // Politica: conservar solo el respaldo mas reciente.
  const entries = await fsp.readdir(dir);
  const previous = entries
    .filter((name) => name.startsWith("logo.previous.") && name.endsWith(".png"))
    .sort();
  for (const stale of previous.slice(0, Math.max(previous.length - 1, 0))) {
    await fsp.rm(path.join(dir, stale), { force: true });
  }
}

export type SaveBrandingLogoInput = {
  bytes: Buffer;
  /** Nombre original: solo se conserva como copia documental, nunca como ruta. */
  originalFilename?: string | null;
};

/**
 * Guarda el logo con escritura ATOMICA: temporal -> validar -> rename.
 *
 * Nunca deja el logo parcialmente escrito.
 */
export async function saveBrandingLogo(input: SaveBrandingLogoInput): Promise<BrandingLogo> {
  const bytes = input.bytes;
  if (!bytes || bytes.length === 0) {
    throw new BrandingValidationError("El archivo esta vacio.", "EMPTY_FILE");
  }
  if (bytes.length > MAX_BRANDING_LOGO_BYTES) {
    throw new BrandingValidationError(
      `El archivo excede el maximo de ${MAX_BRANDING_LOGO_BYTES} bytes.`,
      "FILE_TOO_LARGE",
    );
  }
  if (!detectImageType(bytes)) {
    throw new BrandingValidationError(
      "El archivo no es una imagen PNG o JPG valida.",
      "INVALID_IMAGE",
    );
  }

  const dir = await ensureBrandingDir();
  await backupPreviousLogo(dir);

  const detected = detectImageType(bytes)!;
  await writeFileAtomic(path.join(dir, BRANDING_LOGO_FILENAME), bytes);
  // Copia sin transformar del original: nunca se re-codifica ni se rediseña.
  await writeFileAtomic(path.join(dir, BRANDING_ORIGINAL_FILENAME), bytes);

  const sha256 = crypto.createHash("sha256").update(bytes).digest("hex");
  const metadata = {
    canonicalFilename: BRANDING_LOGO_FILENAME,
    originalFilename: path.basename(input.originalFilename?.trim() || BRANDING_ORIGINAL_FILENAME),
    contentType: detected.contentType,
    extension: detected.extension,
    size: bytes.length,
    sha256,
    updatedAt: new Date().toISOString(),
  };
  await writeFileAtomic(
    path.join(dir, BRANDING_METADATA_FILENAME),
    Buffer.from(`${JSON.stringify(metadata, null, 2)}\n`, "utf8"),
  );

  const stat = await fsp.stat(path.join(dir, BRANDING_LOGO_FILENAME));
  return toLogo(bytes, BRANDING_LOGO_FILENAME, stat.mtime);
}

/** Escritura atomica: temporal -> fsync -> rename. */
async function writeFileAtomic(target: string, bytes: Buffer): Promise<void> {
  const dir = path.dirname(target);
  const tmpPath = path.join(dir, `.tmp-${crypto.randomUUID()}`);
  const handle = await fsp.open(tmpPath, "w", 0o644);
  try {
    await handle.writeFile(bytes);
    await handle.sync();
  } finally {
    await handle.close();
  }
  try {
    await fsp.rename(tmpPath, target);
  } catch (error) {
    await fsp.rm(tmpPath, { force: true });
    throw error;
  }
}

export function decodeBrandingBase64(value: string): Buffer {
  const clean = value.trim().replace(/^data:image\/[a-zA-Z+]+;base64,/, "");
  if (clean.length === 0) {
    throw new BrandingValidationError("Imagen vacia.", "EMPTY_FILE");
  }
  return Buffer.from(clean, "base64");
}
