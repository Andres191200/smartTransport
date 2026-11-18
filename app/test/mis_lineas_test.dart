import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smart_transport/settings/mis_lineas.dart';

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  const a = Linea(Medio.subte, 'A');
  const d = Linea(Medio.subte, 'D');
  const h = Linea(Medio.subte, 'H');

  test('sin nada guardado arranca sin Medios ni Líneas', () async {
    final mis = await MisLineas.load();
    expect(mis.medios, isEmpty);
    expect(mis.lineas, isEmpty);
  });

  test('las Líneas quedan en orden de agregado y no se repiten', () async {
    final mis = await MisLineas.load();
    await mis.agregar(d);
    await mis.agregar(a);
    await mis.agregar(d);

    expect(mis.lineas, [d, a]);
    expect(mis.contiene(a), isTrue);
    expect(mis.contiene(h), isFalse);
  });

  test('agregar una Línea de un Medio no elegido suma el Medio', () async {
    final mis = await MisLineas.load();
    await mis.agregar(d);

    expect(mis.medios, {Medio.subte});
  });

  test('lo guardado se recupera al volver a abrir la app', () async {
    final mis = await MisLineas.load();
    await mis.agregar(h);
    await mis.agregar(a);

    final reabierto = await MisLineas.load();
    expect(reabierto.lineas, [h, a]);
    expect(reabierto.medios, {Medio.subte});
  });

  test('eliminar y deshacer devuelve la Línea a su posición', () async {
    final mis = await MisLineas.load();
    for (final l in [a, d, h]) {
      await mis.agregar(l);
    }

    final eliminada = await mis.eliminar(d);
    expect(mis.lineas, [a, h]);
    expect((await MisLineas.load()).lineas, [a, h]);

    await mis.deshacer(eliminada!);
    expect(mis.lineas, [a, d, h]);
    expect((await MisLineas.load()).lineas, [a, d, h]);
  });

  test('eliminar una Línea que no está no devuelve nada que deshacer', () async {
    final mis = await MisLineas.load();
    expect(await mis.eliminar(d), isNull);
  });

  test('el grupo de un Medio no se borra al quedarse sin Líneas', () async {
    final mis = await MisLineas.load();
    await mis.agregar(d);
    await mis.eliminar(d);

    expect(mis.lineasDe(Medio.subte), isEmpty);
    expect(mis.medios, {Medio.subte});
    expect((await MisLineas.load()).medios, {Medio.subte});
  });

  test('elegir y quitar un Medio se guarda', () async {
    final mis = await MisLineas.load();
    await mis.elegir(Medio.ecobici);
    expect(mis.medios, {Medio.ecobici});
    expect((await MisLineas.load()).medios, {Medio.ecobici});

    await mis.quitar(Medio.ecobici);
    expect(mis.medios, isEmpty);
    expect((await MisLineas.load()).medios, isEmpty);
  });

  test('quitar un Medio descarta sus Líneas y deja las de los demás', () async {
    final mis = await MisLineas.load();
    await mis.agregar(d);
    await mis.elegir(Medio.ecobici);

    await mis.quitar(Medio.subte);
    expect(mis.lineas, isEmpty);
    expect(mis.medios, {Medio.ecobici});
    expect((await MisLineas.load()).lineas, isEmpty);
  });

  group('Onboarding', () {
    test('sin nada guardado no está completado', () async {
      expect((await MisLineas.load()).onboardingCompletado, isFalse);
    });

    test('completarlo guarda sus Medios y Líneas, en orden, y queda completado al reabrir', () async {
      final mis = await MisLineas.load();
      await mis.completarOnboarding(medios: {Medio.subte, Medio.ecobici}, lineas: [h, a]);
      expect(mis.onboardingCompletado, isTrue);

      final reabierto = await MisLineas.load();
      expect(reabierto.onboardingCompletado, isTrue);
      expect(reabierto.medios, {Medio.subte, Medio.ecobici});
      expect(reabierto.lineas, [h, a]);
    });

    test('completarlo sin Medios ni Líneas ("Saltar") también cuenta como completado', () async {
      await (await MisLineas.load()).completarOnboarding(medios: {}, lineas: []);

      final reabierto = await MisLineas.load();
      expect(reabierto.onboardingCompletado, isTrue);
      expect(reabierto.medios, isEmpty);
      expect(reabierto.lineas, isEmpty);
    });

    test('las Líneas suman su Medio aunque no venga entre los Medios', () async {
      final mis = await MisLineas.load();
      await mis.completarOnboarding(medios: {Medio.ecobici}, lineas: [d]);
      expect(mis.medios, {Medio.subte, Medio.ecobici});
    });

    test('se guarda con su versión: si el Onboarding cambia de versión, se vuelve a mostrar', () async {
      await (await MisLineas.load(versionDelOnboarding: 1)).completarOnboarding(medios: {Medio.subte}, lineas: [d]);
      expect((await MisLineas.load(versionDelOnboarding: 1)).onboardingCompletado, isTrue);

      final nuevaVersion = await MisLineas.load(versionDelOnboarding: 2);
      expect(nuevaVersion.onboardingCompletado, isFalse);
      expect(nuevaVersion.lineas, [d], reason: 'Mis líneas no se pierde por cambiar el Onboarding');

      await nuevaVersion.completarOnboarding(medios: {Medio.subte}, lineas: [d]);
      expect((await MisLineas.load(versionDelOnboarding: 2)).onboardingCompletado, isTrue);
    });

    test('la app usa la versión actual del Onboarding', () async {
      await (await MisLineas.load(versionDelOnboarding: MisLineas.versionDelOnboarding))
          .completarOnboarding(medios: {}, lineas: []);
      expect((await MisLineas.load()).onboardingCompletado, isTrue);
    });
  });

  test('avisa a quien lo escucha cuando cambia', () async {
    final mis = await MisLineas.load();
    var avisos = 0;
    mis.addListener(() => avisos++);

    await mis.agregar(d);
    final eliminada = await mis.eliminar(d);
    await mis.deshacer(eliminada!);
    await mis.elegir(Medio.ecobici);
    await mis.quitar(Medio.ecobici);
    await mis.completarOnboarding(medios: {Medio.ecobici}, lineas: [a]);

    expect(avisos, 6);
  });
}
