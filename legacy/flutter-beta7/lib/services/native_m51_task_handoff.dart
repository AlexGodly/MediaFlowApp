import 'package:flutter/foundation.dart';

import '../data/mediaflow_models.dart';
import 'native_m50_task_display.dart';

enum NativeM51HandoffStatus {
  absent,
  ready,
  differentOwner,
  replacedSnapshot,
  changedTask,
  missingOrAmbiguousTitle,
}

@immutable
class NativeM51TaskHandoffView {
  const NativeM51TaskHandoffView({
    required this.status,required this.message,this.title,
    this.categoryId='',this.taskUnit='',this.taskTargetLow=0,
    this.taskTargetHigh=0,
  });
  final NativeM51HandoffStatus status;
  final String message,categoryId,taskUnit;
  final double taskTargetLow,taskTargetHigh;
  final MediaFlowTitle? title;
  bool get ready=>status==NativeM51HandoffStatus.ready && title!=null;
}

/// One-shot, owner-pinned and snapshot-pinned navigation intent.
/// It is neither a v410 log nor a staged draft. A new cloud snapshot
/// invalidates the handoff instead of rebasing against different progress.
class NativeM51TaskHandoff extends ChangeNotifier {
  NativeM51TaskHandoff({required this.ownerId}){
    if(ownerId.isEmpty){throw StateError('Authenticated owner is required');}
  }
  final String ownerId;
  MediaFlowCatalog? _source;
  String? _titleId;
  String _categoryId='',_unit='';
  double _low=0,_high=0;
  bool get hasRequest=>_titleId!=null;

  void request(MediaFlowCatalog catalog,{required String currentOwnerId}){
    if(currentOwnerId!=ownerId){
      throw StateError('Cannot hand off another account task');
    }
    final display=NativeM50TaskDisplay.fromCatalog(catalog);
    if(display.resolution!=NativeM50TitleResolution.exact ||
       display.task==null||display.title==null){
      throw StateError('Task has no unique exact Library title');
    }
    final task=display.task!;
    _source=catalog;
    _titleId=display.title!.id;
    _categoryId=task.categoryId;
    _unit=task.unit;
    _low=task.low;
    _high=task.high;
    notifyListeners();
  }

  NativeM51TaskHandoffView inspect(MediaFlowCatalog catalog,{
      required String currentOwnerId}){
    if(_titleId==null){
      return const NativeM51TaskHandoffView(
        status:NativeM51HandoffStatus.absent,
        message:'No Dashboard task handoff is pending.');
    }
    if(ownerId!=currentOwnerId){
      return const NativeM51TaskHandoffView(
        status:NativeM51HandoffStatus.differentOwner,
        message:'Account changed. Task handoff cannot be used.');
    }
    if(!identical(catalog,_source)){
      return const NativeM51TaskHandoffView(
        status:NativeM51HandoffStatus.replacedSnapshot,
        message:'Library snapshot changed. Return to the Dashboard to '
          'select the current saved task again. Existing drafts were preserved.');
    }
    final task=catalog.sessionActive?catalog.currentTask:null;
    if(task==null||task.libraryId!=_titleId||
       task.categoryId!=_categoryId||task.unit!=_unit||
       task.low!=_low||task.high!=_high){
      return const NativeM51TaskHandoffView(
        status:NativeM51HandoffStatus.changedTask,
        message:'Current task changed. Review the updated Dashboard first.');
    }
    MediaFlowTitle? resolved;
    for(final item in catalog.library){
      if(item.id!=_titleId){continue;}
      if(resolved!=null){
        return const NativeM51TaskHandoffView(
          status:NativeM51HandoffStatus.missingOrAmbiguousTitle,
          message:'Duplicate Library title IDs block this handoff.');
      }
      resolved=item;
    }
    if(resolved==null){
      return const NativeM51TaskHandoffView(
        status:NativeM51HandoffStatus.missingOrAmbiguousTitle,
        message:'Saved task Library title is missing.');
    }
    return NativeM51TaskHandoffView(
      status:NativeM51HandoffStatus.ready,
      message:'Review the saved task title. No progress or History '
        'changes are performed by navigating.',
      title:resolved,categoryId:_categoryId,taskUnit:_unit,
      taskTargetLow:_low,taskTargetHigh:_high);
  }

  void dismiss(){
    _source=null;_titleId=null;
    _categoryId='';_unit='';_low=0;_high=0;
    notifyListeners();
  }
}
