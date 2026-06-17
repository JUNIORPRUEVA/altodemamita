param(
  [string]$Identifier = ''
)

$dbPath = Join-Path $env:LOCALAPPDATA 'SistemaSolares\data\database\sistema_solares.db'
Write-Output "[LocalAuthDebug] db_path=$dbPath"

if (!(Test-Path $dbPath)) {
  Write-Output '[LocalAuthDebug] db_not_found=true'
  exit 1
}

if (-not (Get-Command sqlite3.exe -ErrorAction SilentlyContinue)) {
  Write-Output '[LocalAuthDebug] sqlite3_not_found=true'
  exit 1
}

& sqlite3.exe $dbPath ".headers on" ".mode column" "SELECT COUNT(*) AS local_users_count FROM usuarios;"
& sqlite3.exe $dbPath ".headers on" ".mode column" "SELECT id, email, CASE WHEN instr(lower(trim(email)),'@') > 0 THEN substr(lower(trim(email)),1,instr(lower(trim(email)),'@')-1) ELSE '' END AS username, id_remote, remote_auth_id, activo AS is_active, deleted_at, CASE WHEN trim(COALESCE(password_hash,''))='' THEN 1 ELSE 0 END AS password_hash_empty, length(COALESCE(password_hash,'')) AS password_hash_length, sync_status, auth_source, last_online_login_at FROM usuarios ORDER BY id;"

if ($Identifier.Trim().Length -gt 0) {
  $normalized = $Identifier.Trim().ToLowerInvariant()
  Write-Output "[LocalAuthDebug] identifier_original=$Identifier"
  Write-Output "[LocalAuthDebug] identifier_normalized=$normalized"
  & sqlite3.exe $dbPath ".headers on" ".mode column" "SELECT COUNT(*) AS found_by_email FROM usuarios WHERE deleted_at IS NULL AND lower(trim(email)) = '$normalized';"
  & sqlite3.exe $dbPath ".headers on" ".mode column" "SELECT COUNT(*) AS found_by_username FROM usuarios WHERE deleted_at IS NULL AND lower(trim(CASE WHEN instr(COALESCE(email,''),'@') > 0 THEN substr(COALESCE(email,''),1,instr(COALESCE(email,''),'@')-1) ELSE '' END)) = '$normalized';"
  & sqlite3.exe $dbPath ".headers on" ".mode column" "SELECT COUNT(*) AS found_by_remote_ids FROM usuarios WHERE deleted_at IS NULL AND (lower(trim(COALESCE(remote_auth_id,''))) = '$normalized' OR lower(trim(COALESCE(id_remote,''))) = '$normalized');"
  & sqlite3.exe $dbPath ".headers on" ".mode column" "SELECT id, email, CASE WHEN instr(lower(trim(email)),'@') > 0 THEN substr(lower(trim(email)),1,instr(lower(trim(email)),'@')-1) ELSE '' END AS username, id_remote, remote_auth_id, activo AS is_active, deleted_at, CASE WHEN trim(COALESCE(password_hash,''))='' THEN 1 ELSE 0 END AS password_hash_empty, length(COALESCE(password_hash,'')) AS password_hash_length, sync_status, auth_source, last_online_login_at FROM usuarios WHERE deleted_at IS NULL AND (lower(trim(email)) = '$normalized' OR lower(trim(CASE WHEN instr(COALESCE(email,''),'@') > 0 THEN substr(COALESCE(email,''),1,instr(COALESCE(email,''),'@')-1) ELSE '' END)) = '$normalized' OR lower(trim(COALESCE(remote_auth_id,''))) = '$normalized' OR lower(trim(COALESCE(id_remote,''))) = '$normalized') LIMIT 1;"
}
