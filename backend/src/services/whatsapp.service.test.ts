import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { normalizeWhatsappPhone } from './whatsapp.service';

describe('normalizeWhatsappPhone', () => {
  it('normaliza telefonos dominicanos de 10 digitos', () => {
    assert.equal(normalizeWhatsappPhone('8095551234'), '18095551234');
    assert.equal(normalizeWhatsappPhone('(829) 555-1234'), '18295551234');
    assert.equal(normalizeWhatsappPhone('849-555-1234'), '18495551234');
    assert.equal(normalizeWhatsappPhone('+1 (829) 555-1234'), '18295551234');
    assert.equal(normalizeWhatsappPhone('001-829-555-1234'), '18295551234');
  });

  it('rechaza telefonos vacios o invalidos', () => {
    assert.equal(normalizeWhatsappPhone(''), null);
    assert.equal(normalizeWhatsappPhone('5551234'), null);
  });
});
