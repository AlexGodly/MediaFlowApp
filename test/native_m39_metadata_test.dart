import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/data/mediaflow_full_state.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/features/library/library_screen.dart';
import 'package:mediaflow_app/services/native_m39_metadata.dart';
import 'package:mediaflow_app/services/native_m37_library_plan.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_snapshot_codec.dart';

MediaFlowCatalog _catalog() => decodeMediaFlowState({
  'categories':[{'id':'anime','name':'Anime'}],
  'library':[{
    'id':'show-1','title':'Seasonal Test','categoryId':'anime',
    'status':'active','priority':'medium','progress':2,'total':12,
    'externalIds':{'mal':'123','custom_service':'special-1'},
    'v377ManualExternalIds':{'imdb':null},
    'providerMetadata':{'unknown':'do not touch'},
    'seasonSource':'simkl',
    'seasons':[{
      'id':'s1','name':'Season 1','number':1,'progress':2,'total':12,
      'source':'simkl','manual':false,'synthetic':false,
      'unknownSeason':{'nested':'keep'}
    }],
  }],
  'sessions':[], 'settings':{},
});

class _Repo extends MediaFlowLibraryRepository {
  _Repo(this.value);
  final MediaFlowCatalog value;
  @override
  Future<MediaFlowCatalog> load() async => value;
}

void main() {
  test('v377 IDs support intentional manual clears and unknown providers', () {
    final original = <String,String>{'mal':'100','custom_service':'hi-1'};
    final manual = <String,String?>{'imdb':null};
    final next = NativeM39Metadata.applyIdChanges(original,manual,{
      'mal':null, 'simkl':'42',
    });
    expect(next.ids['mal'],isNull);
    expect(next.ids['simkl'],'42');
    expect(next.ids['custom_service'],'hi-1');
    expect(next.manual['mal'],isNull);
    expect(next.manual.containsKey('mal'),true);
    expect(next.manual['imdb'],isNull);
    expect(()=>NativeM39Metadata.applyIdChanges(original,manual,{
      'imdb':'bad'}),throwsFormatException);
    expect(()=>NativeM39Metadata.applyIdChanges(original,manual,{
      'mal':'0'}),throwsFormatException);
    expect(()=>NativeM39Metadata.applyIdChanges(original,manual,{
      'illegal space':'abc'}),throwsFormatException);
  });

  test('season rows drive aggregate and reject malformed IDs/numbers', () {
    const first=MediaFlowSeason('Season 1',3,12,id:'s1',number:1);
    const second=MediaFlowSeason('Season 2',1,null,id:'s2',number:2);
    final a=NativeM39Metadata.aggregate([first,second]);
    expect(a.progress,4);
    expect(a.total,12);
    expect(()=>NativeM39Metadata.aggregate([first,first]),
      throwsFormatException);
    expect(()=>NativeM39Metadata.aggregate([
      const MediaFlowSeason('Broken',13,12,id:'bad'),
    ]),throwsFormatException);
    expect(()=>NativeM39Metadata.aggregate([
      const MediaFlowSeason('Broken',1,12,id:'bad',number:1.5),
    ]),throwsFormatException);
  });

  test('ID+season edits stage atomically, preserve source and undo/redo', () {
    final source=_catalog();
    final plan=NativeM37LibraryPlan(ownerId:'owner')..observe(source);
    final old=source.library.single;
    final season=MediaFlowSeason('Season 1',5,12,id:'s1',number:1,
      source:'manual',manual:true);
    plan.editM39('show-1',idChanges:{'mal':null,'anilist':'777'},
      seasons:[season]);
    expect(plan.editCount,1);
    expect(plan.fieldsFor('show-1').externalIds['mal'],isNull);
    expect(plan.fieldsFor('show-1').manualExternalIds.containsKey('mal'),true);
    expect(plan.fieldsFor('show-1').manualExternalIds['mal'],isNull);
    expect(plan.fieldsFor('show-1').externalIds['custom_service'],'special-1');
    expect(plan.previewCatalog().library.single.progress,5);
    expect(plan.previewCatalog().library.single.total,12);
    expect(plan.previewCatalog().library.single.seasonSource,'manual');
    expect(old.progress,2);
    expect(old.externalIds['mal'],'123');
    plan.undo();
    expect(plan.editCount,0);
    expect(plan.previewCatalog().library.single.progress,2);
    plan.redo();
    expect(plan.fieldsFor('show-1').externalIds['anilist'],'777');
    plan.dispose();
  });

  test('ordinary edits and batch patches retain staged ID and season fields',(){
    final src=_catalog();
    final plan=NativeM37LibraryPlan(ownerId:'owner')..observe(src);
    plan.editM39('show-1',idChanges:{'imdb':'tt1234567'});
    final first=plan.fieldsFor('show-1');
    plan.edit('show-1', NativeM37Fields(
      title:'Renamed',categoryId:first.categoryId,status:first.status,
      priority:first.priority,progress:first.progress,total:first.total,
      rating:first.rating,coverUrl:first.coverUrl,
      description:first.description,tags:first.tags,
      seasons:first.seasons,externalIds:first.externalIds,
      manualExternalIds:first.manualExternalIds,seasonSource:first.seasonSource));
    plan.batchEdit(['show-1'],priority:'high');
    expect(plan.fieldsFor('show-1').externalIds['imdb'],'tt1234567');
    expect(plan.fieldsFor('show-1').seasons.single.id,'s1');
    expect(plan.fieldsFor('show-1').title,'Renamed');
    expect(plan.fieldsFor('show-1').priority,'high');
    plan.dispose();
  });

  test('stale snapshot, invalid seasons and duplicate identities fail closed',(){
    final src=_catalog();
    final plan=NativeM37LibraryPlan(ownerId:'owner')..observe(src);
    expect(()=>plan.editM39('show-1', idChanges:{'mal':'abc'}),
      throwsFormatException);
    expect(()=>plan.editM39('show-1', seasons:[]),
      throwsFormatException);
    expect(plan.changeCount,0);
    plan.editM39('show-1',idChanges:{'mal':'999'});
    plan.observe(_catalog());
    expect(plan.stale,true);
    expect(()=>plan.editM39('show-1',idChanges:{'mal':'12'}),
      throwsStateError);
    plan.dispose();
  });

  test('raw v410 full-state simulation preserves unknown nested metadata',(){
    final raw=jsonDecode(
      File('test/fixtures/m28_v410_lossless_sample.json').readAsStringSync());
    final full=MediaFlowFullState.parse(raw);
    final old=jsonDecode(jsonEncode(full.json));
    final season=MediaFlowSeason('Season 1',7,12,id:'s1',
      number:1,source:'manual',manual:true);
    final other=MediaFlowSeason('Season 2',0,12,id:'s2',number:2);
    final changed=full.simulateTitleMetadata(
      titleId:'v410-1',
      idChanges:{'mal':'123456','imdb':'tt1234567'},
      seasons:[season,other]);
    final row=(changed.json['library'] as List).first as Map;
    expect(row['externalIds']['mal'],'123456');
    expect(row['v377ManualExternalIds']['mal'],'123456');
    expect(row['seasons'][0]['futureSeason']['providerIds']['one'],543);
    expect(row['providerMetadata'],(old['library'] as List).first['providerMetadata']);
    expect(row['unknownMarker'],99);
    expect(row['progress'],7);
    expect(row['total'],24);
    expect(changed.json['sessions'],old['sessions']);
    expect(changed.json['settings'],old['settings']);
    expect(changed.json['xpLedger'],old['xpLedger']);
    expect(full.json,old);
    expect(changed.isLocalSimulation,true);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    expect(()=>full.simulateTitleMetadata(
      titleId:'missing',idChanges:{'mal':'42'}),throwsStateError);
    expect(()=>full.simulateTitleMetadata(
      titleId:'v410-1',idChanges:{'mal':'0'}),throwsFormatException);
    expect(()=>full.simulateTitleMetadata(
      titleId:'v410-1',seasons:[
        const MediaFlowSeason('Unknown',1,5,id:'unknown'),
      ]),throwsFormatException);
    expect(NativeSnapshotCodec.equivalent(full.json,old),true);
  });

  testWidgets('native Title Details exposes editable IDs and a season draft',
      (tester) async {
    final source=_catalog();
    final plan=NativeM37LibraryPlan(ownerId:'owner');
    tester.view.physicalSize=const Size(900,1000);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:LibraryScreen(repository:_Repo(source),changePlan:plan))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seasonal Test').first);
    await tester.pumpAndSettle();
    expect(find.text('External Media IDs'),findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('m39-edit-metadata')));
    await tester.tap(find.byKey(const Key('m39-edit-metadata')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m39-metadata-sheet')),findsOneWidget);
    await tester.enterText(find.byKey(const Key('m39-id-mal')),'1234');
    await tester.ensureVisible(find.byKey(const Key('m39-stage-metadata')));
    await tester.tap(find.byKey(const Key('m39-stage-metadata')));
    await tester.pumpAndSettle();
    expect(plan.fieldsFor('show-1').externalIds['mal'],'1234');
    expect(plan.fieldsFor('show-1').seasonSource,'simkl');
    expect(plan.fieldsFor('show-1').seasons.single.source,'simkl');
    expect(source.library.single.externalIds['mal'],'123');
    plan.dispose();
  });
}
