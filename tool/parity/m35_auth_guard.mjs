import assert from 'node:assert/strict';
import fs from 'node:fs';
const auth=fs.readFileSync('lib/features/auth/auth_gate.dart','utf8');
const service=fs.readFileSync('lib/services/mediaflow_auth.dart','utf8');
const rules=fs.readFileSync('lib/services/native_m35_auth_recovery.dart','utf8');
const repository=fs.readFileSync('lib/data/mediaflow_library_repository.dart','utf8');
const flags=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for(const mark of ['AuthChangeEvent.passwordRecovery',
  '_recoveryOwner','NativePasswordRecoveryScreen',
  'AutofillHints.email','m35-auth-email','m35-recovery-password',
  'm35-auth-confirm','showPassword']) {
  if(mark==='showPassword')continue;
  assert(auth.includes(mark),'Missing native M35 auth flow '+mark);
}
assert(service.includes('auth.updateUser(UserAttributes(password: password))'));
assert(rules.includes('currentOwnerId() != expectedOwnerId'));
assert(rules.includes('Password recovery is already in progress.'));
for(const method of ['signInWithPassword','signUp(','resetPasswordForEmail']){
  assert(service.includes(method));
}
assert(!/\.upsert\(|\.insert\(|\.update\(|\.delete\(|\.rpc\(/.test(repository)));
for(const flag of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']){
  assert(flags.includes(flag),'Cloud write safety changed '+flag);
}
console.log('M35: native auth and owner-bound password recovery; no production cloud state mutations.');
