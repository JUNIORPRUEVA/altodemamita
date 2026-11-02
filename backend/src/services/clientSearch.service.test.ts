import assert from "node:assert/strict";
import test from "node:test";
import {
  foldSearchText,
  foldedColumnSql,
  searchDigits,
  searchTokens,
} from "./clientSearch.service";

test("foldSearchText pliega acentos y minusculas", () => {
  assert.equal(foldSearchText("José Ramón Peña"), "jose ramon pena");
  assert.equal(foldSearchText("ILUMINADA RODRÍGUEZ OZUNA"), "iluminada rodriguez ozuna");
  assert.equal(foldSearchText("Núñez"), "nunez");
});

test("foldSearchText colapsa espacios y tolera vacios", () => {
  assert.equal(foldSearchText("  jose   ramon  "), "jose ramon");
  assert.equal(foldSearchText(""), "");
  assert.equal(foldSearchText(null), "");
  assert.equal(foldSearchText(undefined), "");
});

test("searchTokens separa palabras, ignora espacios y limita a 6", () => {
  assert.deepEqual(searchTokens("  Peña   Jose "), ["pena", "jose"]);
  assert.deepEqual(searchTokens(""), []);
  assert.equal(searchTokens("a b c d e f g h").length, 6);
});

test("searchDigits deja solo numeros", () => {
  assert.equal(searchDigits("001-1234567-8"), "00112345678");
  assert.equal(searchDigits("(809) 555 1234"), "8095551234");
  assert.equal(searchDigits("sin numeros"), "");
});

test("foldedColumnSql usa translate con mapas del mismo largo", () => {
  const sql = foldedColumnSql("name");
  assert.match(sql, /^translate\(lower\(coalesce\(name, ''\)\), '[^']+', '[^']+'\)$/);
  const match = sql.match(/'([^']+)', '([^']+)'\)$/) ?? [];
  const from = match[1];
  const to = match[2];
  assert.ok(from && to, sql);
  assert.equal([...from].length, 24);
  assert.equal([...from].length, [...to].length);
});
