import { Router } from "express";
import { authGuard } from "../auth";

export const deviceRouter = Router();

/**
 * GET /devices/current
 *
 * Contrato que consume la app Windows en
 * `app_local/lib/core/system/system_config_service.dart`
 * (`_refreshCurrentDevice`):
 *
 *   { data: { isPrimary: boolean, canWrite: boolean, reason?: string } }
 *
 * Sin esta respuesta el cliente conserva su estado persistido por defecto
 * ("bloqueado hasta validar"), `canAccess(...)` devuelve false para toda
 * escritura y la app queda en solo lectura incluso para un ADMINISTRADOR:
 * no se puede registrar un pago, anularlo ni corregirlo.
 *
 * Sistema Solares es de UNA sola empresa y la instalacion Windows es el equipo
 * operativo del cliente. La autorizacion por dispositivo es politica LEGACY:
 * aun no existe modelo `Device` ni registro real de equipos (TARGET pendiente,
 * documentado en docs/ARCHITECTURE.md). Mientras no exista, el equipo
 * autenticado se declara primario y con permiso de escritura.
 *
 * Cuando se implemente el registro real de dispositivos, este handler debe
 * consultar la tabla correspondiente y devolver `canWrite: false` para los
 * equipos secundarios.
 */
deviceRouter.get("/current", authGuard, (req, res) => {
  return res.json({
    data: {
      deviceId: (req.header("x-device-id") ?? "").trim(),
      isPrimary: true,
      canWrite: true,
      reason: "",
      validatedAt: new Date().toISOString(),
      policy: "legacy_single_device",
    },
  });
});
