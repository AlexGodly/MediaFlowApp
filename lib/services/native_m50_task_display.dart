import '../data/mediaflow_models.dart';

/// Lossy-but-safe display projection of a saved v410 task. Never derives an
/// ID from the display title or labels an unverified source as confirmed.
enum NativeM50TitleResolution { inactive, missingId, missingTitle, ambiguousId, exact }

class NativeM50TaskDisplay {
  const NativeM50TaskDisplay({
    required this.task, required this.category,
    required this.resolution, required this.title,
    required this.showCover, required this.progressPercent,
  });

  final MediaFlowTask? task;
  final MediaFlowCategory? category;
  final NativeM50TitleResolution resolution;
  final MediaFlowTitle? title;
  final bool showCover;
  final double? progressPercent;

  bool get active => task != null;
  String get categoryName => category?.name ??
      (task?.categoryId.isNotEmpty == true ? task!.categoryId : 'Task');
  String get recommendedName => task?.title.isNotEmpty == true
      ? task!.title : (title?.title ?? 'Title not specified');
  String get sourceClaim {
    final source=task?.orderSource;
    if(source == null) { return 'No saved source annotation'; }
    if(source.type=='collection') {
      return 'Saved source claim: Collection (not independently verified)';
    }
    if(source.type=='title') {
      return 'Saved source claim: Direct Personal Order title (not independently verified)';
    }
    return 'Saved source annotation is unrecognized';
  }
  String get resolutionNote => switch(resolution){
    NativeM50TitleResolution.inactive =>
      'No active task. Start a session on the original MediaFlow website.',
    NativeM50TitleResolution.missingId =>
      'Exact Library ID unavailable; cover and progress cannot be verified.',
    NativeM50TitleResolution.missingTitle =>
      'Saved Library ID no longer resolves to a title.',
    NativeM50TitleResolution.ambiguousId =>
      'Saved Library ID appears more than once. Cover and progress hidden.',
    NativeM50TitleResolution.exact => 'Exact Library title resolved from saved ID.',
  };
  String? get safeCoverUrl {
    if(!showCover || title==null) { return null; }
    final raw=title!.coverUrl.trim();
    final uri=Uri.tryParse(raw);
    if(uri == null || uri.scheme!='https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) { return null; }
    return raw;
  }

  /// Scan only for the saved exact ID. Duplicate IDs fail closed instead
  /// of silently showing a different title's poster or progress.
  factory NativeM50TaskDisplay.fromCatalog(MediaFlowCatalog catalog) {
    final task=catalog.sessionActive?catalog.currentTask:null;
    final category=task==null?null:catalog.categoryById[task.categoryId];
    if(task==null) {
      return const NativeM50TaskDisplay(
        task:null,category:null,resolution:NativeM50TitleResolution.inactive,
        title:null,showCover:false,progressPercent:null);
    }
    if(task.libraryId.isEmpty) {
      return NativeM50TaskDisplay(
        task:task,category:category,
        resolution:NativeM50TitleResolution.missingId,
        title:null,showCover:false,progressPercent:null);
    }
    MediaFlowTitle? found;
    for(final candidate in catalog.library) {
      if(candidate.id!=task.libraryId) { continue; }
      if(found!=null) {
        return NativeM50TaskDisplay(
          task:task,category:category,
          resolution:NativeM50TitleResolution.ambiguousId,
          title:null,showCover:false,progressPercent:null);
      }
      found=candidate;
    }
    if(found==null) {
      return NativeM50TaskDisplay(
        task:task,category:category,
        resolution:NativeM50TitleResolution.missingTitle,
        title:null,showCover:false,progressPercent:null);
    }
    final total=found.total;
    final progress=found.progress;
    final percent=total!=null && total.isFinite && total>0 &&
        progress.isFinite ? (progress/total).clamp(0.0,1.0).toDouble() : null;
    return NativeM50TaskDisplay(
      task:task,category:category,
      resolution:NativeM50TitleResolution.exact,
      title:found,showCover:true,progressPercent:percent);
  }
}
