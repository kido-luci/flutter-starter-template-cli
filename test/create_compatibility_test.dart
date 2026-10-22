import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_starter_template_cli/flutter_starter_template_cli.dart';
import 'package:flutter_starter_template_cli/src/commands/create_command.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:test/test.dart';

void main() {
  group('create compatibility matrix', () {
    test('accepts every documented supported shape', () {
      final supported = [
        _shape(),
        _shape(useFirebase: false),
        _shape(useAuth: false),
        _shape(useBackend: false, useAuth: false),
        _shape(useBackend: false, useAuth: true),
        _shape(
          minimal: true,
          useFirebase: false,
          useBackend: false,
          useAuth: false,
        ),
        _shape(authProvider: 'firebase'),
      ];

      for (final shape in supported) {
        expect(
          validateCreateCompatibility(
            minimal: shape.minimal,
            useFirebase: shape.useFirebase,
            useBackend: shape.useBackend,
            useAuth: shape.useAuth,
            authProvider: shape.authProvider,
          ),
          isNull,
        );
      }
    });

    test('rejects contradictory minimal flags', () {
      expect(
        validateCreateCompatibility(
          minimal: true,
          useFirebase: false,
          useBackend: false,
          useAuth: false,
          authProvider: 'jwt',
          firebaseExplicitlyEnabled: true,
        ),
        contains('--minimal disables Firebase'),
      );
      expect(
        validateCreateCompatibility(
          minimal: true,
          useFirebase: false,
          useBackend: false,
          useAuth: false,
          authProvider: 'jwt',
          backendExplicitlyEnabled: true,
        ),
        contains('--minimal disables the backend'),
      );
      expect(
        validateCreateCompatibility(
          minimal: true,
          useFirebase: false,
          useBackend: false,
          useAuth: false,
          authProvider: 'jwt',
          authExplicitlyEnabled: true,
        ),
        contains('--minimal disables authentication'),
      );
    });

    test('rejects provider and URL flags without their required pillars', () {
      expect(
        validateCreateCompatibility(
          minimal: false,
          useFirebase: true,
          useBackend: false,
          useAuth: false,
          authProvider: 'jwt',
          authProviderWasParsed: true,
        ),
        contains('--auth-provider has no effect'),
      );
      expect(
        validateCreateCompatibility(
          minimal: false,
          useFirebase: false,
          useBackend: true,
          useAuth: true,
          authProvider: 'firebase',
          authProviderWasParsed: true,
        ),
        contains('requires Firebase'),
      );
      expect(
        validateCreateCompatibility(
          minimal: false,
          useFirebase: false,
          useBackend: false,
          useAuth: false,
          authProvider: 'jwt',
          apiUrlWasParsed: true,
        ),
        contains('--api-url has no consumer'),
      );
    });

    test('rejects Document Center without Document Engine', () {
      expect(
        validateCreateCompatibility(
          minimal: false,
          useFirebase: true,
          useBackend: true,
          useAuth: true,
          authProvider: 'jwt',
          useDocumentEngine: false,
          useDocumentCenter: false,
          documentCenterExplicitlyEnabled: true,
        ),
        contains('--document-center requires Document Engine'),
      );
    });

    test('accepts engine-only and document-free project shapes', () {
      for (final shape in const [
        (engine: true, center: false),
        (engine: false, center: false),
      ]) {
        expect(
          validateCreateCompatibility(
            minimal: false,
            useFirebase: true,
            useBackend: true,
            useAuth: true,
            authProvider: 'jwt',
            useDocumentEngine: shape.engine,
            useDocumentCenter: shape.center,
          ),
          isNull,
        );
      }
    });

    test('command rejects a conflict before creating the output directory',
        () async {
      final temp = Directory.systemTemp.createTempSync('fst-compatibility-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final output = Directory('${temp.path}/must-not-exist');
      final runner = CommandRunner<int>('fst', 'test')
        ..addCommand(CreateCommand(Logger()));

      final result = await runner.run([
        'create',
        '--yes',
        '--name',
        'Conflict App',
        '--bundle-id',
        'com.example.conflict',
        '--org',
        'Example',
        '--output-dir',
        output.path,
        '--template-path',
        '${temp.path}/missing-template',
        '--no-setup',
        '--minimal',
        '--firebase',
      ]);

      expect(result, 1);
      expect(output.existsSync(), isFalse);
    });
  });
}

({
  bool minimal,
  bool useFirebase,
  bool useBackend,
  bool useAuth,
  String authProvider,
}) _shape({
  bool minimal = false,
  bool useFirebase = true,
  bool useBackend = true,
  bool useAuth = true,
  String authProvider = 'jwt',
}) =>
    (
      minimal: minimal,
      useFirebase: useFirebase,
      useBackend: useBackend,
      useAuth: useAuth,
      authProvider: authProvider,
    );
