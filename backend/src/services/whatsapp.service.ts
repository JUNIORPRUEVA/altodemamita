import { config } from '../config';

export type WhatsappTemplateMessage = {
  to: string;
  templateName: string;
  languageCode?: string;
  parameters?: string[];
  components?: unknown[];
};

export type WhatsappSendResult = {
  messageId: string;
  httpStatus: number;
  raw: unknown;
};

export class WhatsappService {
  async sendTemplateMessage(message: WhatsappTemplateMessage): Promise<WhatsappSendResult> {
    const response = await fetch(
      `https://graph.facebook.com/v20.0/${config.whatsappPhoneNumberId}/messages`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${config.whatsappAccessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          messaging_product: 'whatsapp',
          to: message.to,
          type: 'template',
          template: {
            name: message.templateName,
            language: { code: message.languageCode ?? 'es' },
            components: message.components ?? [
              {
                type: 'body',
                parameters: (message.parameters ?? []).map((text) => ({
                  type: 'text',
                  text,
                })),
              },
            ],
          },
        }),
      },
    );
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(`WhatsApp API error ${response.status}: ${safeErrorMessage(body)}`);
    }
    const messageId = (body as any)?.messages?.[0]?.id;
    if (!messageId) {
      throw new Error('WhatsApp API no devolvio message id.');
    }
    return { messageId, httpStatus: response.status, raw: body };
  }
}

export function normalizeWhatsappPhone(phone?: string | null) {
  let digits = String(phone ?? '').replace(/\D/g, '');
  if (digits.startsWith('00')) {
    digits = digits.slice(2);
  }
  if (!digits) return null;
  if (digits.length === 10 && ['809', '829', '849'].includes(digits.slice(0, 3))) {
    return `1${digits}`;
  }
  if (digits.length === 11 && digits.startsWith('1')) return digits;
  return null;
}

function safeErrorMessage(body: unknown) {
  const message = (body as any)?.error?.message;
  return typeof message === 'string' ? message.slice(0, 240) : 'respuesta invalida';
}
