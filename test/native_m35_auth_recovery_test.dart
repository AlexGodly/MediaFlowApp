import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mediaflow_app/features/auth/auth_gate.dart';
import 'package:mediaflow_app/services/mediaflow_auth.dart';
import 'package:mediaflow_app/services/native_m35_auth_recovery.dart';

void main() {
  final fakeClient=SupabaseClient(
    'https://test.invalid.supabase.co',
    'test-key-nonproduction-only',
  );

  test('v410-compatible basic signup/login email and password rules', () {
    expect(NativeM35AuthRules.email('user@example.com'), isNull);
    expect(NativeM35AuthRules.email(' user@example.com '), isNull);
    expect(NativeM35AuthRules.email('user@'), isNotNull);
    expect(NativeM35AuthRules.email('user example@example.com'),isNotNull);
    expect(NativeM35AuthRules.email('user@example'),isNotNull);
    expect(NativeM35AuthRules.password('12345'),isNotNull);
    expect(NativeM35AuthRules.password('123456'),isNull);
    expect(NativeM35AuthRules.confirmation('123456','000000'),
      'Passwords do not match.');
    expect(NativeM35AuthRules.confirmation('123456','123456'),isNull);
  });

  test('password update is blocked if owner no longer matches', () async {
    var calls=0;
    final flow=NativeM35PasswordRecovery(
      expectedOwnerId:'alice',
      currentOwnerId:()=>'bob',
      updatePassword:(_) async { calls++; },
    );
    await expectLater(flow.complete('abcdef','abcdef'),throwsStateError);
    expect(calls,0);
  });

  test('invalid or unconfirmed password never calls Supabase Auth', () async {
    var calls=0;
    final flow=NativeM35PasswordRecovery(
      expectedOwnerId:'alice',
      currentOwnerId:()=>'alice',
      updatePassword:(_) async { calls++; },
    );
    await expectLater(flow.complete('abc','abc'),throwsFormatException);
    await expectLater(flow.complete('abcabc','wrong!'),throwsFormatException);
    expect(calls,0);
    expect(flow.busy,isFalse);
  });

  test('successful update verifies session before and after credential call',
      () async {
    String? account='alice';
    var calls=0;
    final flow=NativeM35PasswordRecovery(
      expectedOwnerId:'alice',
      currentOwnerId:()=>account,
      updatePassword:(password) async {
        expect(password,'goodsecret');
        calls++;
      },
    );
    await flow.complete('goodsecret','goodsecret');
    expect(calls,1);
    expect(flow.busy,false);
    account='bob';
    await expectLater(flow.complete('goodsecret','goodsecret'),
      throwsStateError);
    expect(calls,1);
  });

  test('owner switches while password update is pending: no false success',
      () async {
    String? owner='alice';
    final flow=NativeM35PasswordRecovery(
      expectedOwnerId:'alice',
      currentOwnerId:()=>owner,
      updatePassword:(_) async {
        owner='bob';
      },
    );
    await expectLater(flow.complete('secret6','secret6'),throwsStateError);
    expect(flow.busy,false);
  });

  test('recovery prevents duplicate submissions and resets after failure',
      () async {
    final completer=Future<void>.delayed(const Duration(milliseconds:15));
    var calls=0;
    final flow=NativeM35PasswordRecovery(
      expectedOwnerId:'alice',
      currentOwnerId:()=>'alice',
      updatePassword:(_) async {
        calls++;
        await completer;
        throw StateError('Network');
      },
    );
    final started=flow.complete('secret6','secret6');
    await expectLater(flow.complete('secret6','secret6'),throwsStateError);
    await expectLater(started,throwsStateError);
    expect(calls,1);
    expect(flow.busy,false);
  });

  testWidgets('mobile auth screen fits narrow phone and allows visibility toggle',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize=const Size(340,760);
    tester.view.devicePixelRatio=1;
    await tester.pumpWidget(MaterialApp(
      home:SignInScreen(auth:MediaFlowAuth(fakeClient)),
    ));
    await tester.pump();
    expect(find.text('Welcome back to MediaFlow'),findsOneWidget);
    expect(find.byKey(const Key('m35-auth-email')),findsOneWidget);
    expect(find.byKey(const Key('m35-auth-password')),findsOneWidget);
    final input=tester.widget<TextField>(
      find.byKey(const Key('m35-auth-password')));
    expect(input.obscureText,true);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(
      find.byKey(const Key('m35-auth-password'))).obscureText,false);
    expect(tester.takeException(),isNull);
  });

  testWidgets('signup checks confirmation and clears password on mode switch',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SignInScreen(auth:MediaFlowAuth(fakeClient)),
    ));
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.byKey(const Key('m35-auth-confirm')),findsOneWidget);
    await tester.enterText(find.byKey(const Key('m35-auth-email')),
        'user@example.com');
    await tester.enterText(find.byKey(const Key('m35-auth-password')),
        'password123');
    await tester.enterText(find.byKey(const Key('m35-auth-confirm')),
        'different');
    await tester.tap(find.byKey(const Key('m35-auth-submit')));
    await tester.pump();
    expect(find.text('Passwords do not match.'),findsOneWidget);
    await tester.tap(find.text('Already have an account? Log in'));
    await tester.pump();
    expect(find.byKey(const Key('m35-auth-confirm')),findsNothing);
    expect(tester.widget<TextField>(
        find.byKey(const Key('m35-auth-password')))
        .controller!.text,isEmpty);
  });

  testWidgets('forgot password refuses invalid email before touching network',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SignInScreen(auth:MediaFlowAuth(fakeClient)),
    ));
    await tester.tap(find.byKey(const Key('m35-auth-forgot')));
    await tester.pump();
    expect(find.textContaining('Enter your valid email'),findsOneWidget);
  });

  testWidgets('recovery cannot submit mismatched password; success fires once',
      (tester) async {
    var called=0,completed=0;
    final flow=NativeM35PasswordRecovery(
      expectedOwnerId:'alice',
      currentOwnerId:()=>'alice',
      updatePassword:(value) async {
        called++;
        expect(value,'securepass');
      },
    );
    await tester.pumpWidget(MaterialApp(
      home:NativePasswordRecoveryScreen(
        auth:MediaFlowAuth(fakeClient),
        ownerId:'alice',testCoordinator:flow,
        onRecovered:()=>completed++,
      ),
    ));
    await tester.enterText(find.byKey(const Key('m35-recovery-password')),
        'securepass');
    await tester.enterText(find.byKey(const Key('m35-recovery-confirm')),
        'notmatch');
    await tester.tap(find.byKey(const Key('m35-recovery-submit')));
    await tester.pump();
    expect(find.text('Passwords do not match.'),findsOneWidget);
    expect(called,0);
    await tester.enterText(find.byKey(const Key('m35-recovery-confirm')),
        'securepass');
    await tester.tap(find.byKey(const Key('m35-recovery-submit')));
    await tester.pump();
    expect(called,1);
    expect(completed,1);
  });
}
