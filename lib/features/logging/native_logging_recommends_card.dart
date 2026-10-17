import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_logging_recommends.dart';
import '../../services/native_m43_recommendation_audit.dart';

/// v478-inspired MediaFlow Recommends shortcut in native Logging.
/// Adding a recommendation only changes the transient local title selection.
class NativeLoggingRecommendsCard extends StatefulWidget {
  const NativeLoggingRecommendsCard({
    super.key,required this.catalog,required this.selectedIds,
    required this.onUse,
  });
  final MediaFlowCatalog catalog;
  final Set<String> selectedIds;
  final ValueChanged<MediaFlowTitle> onUse;

  @override
  State<NativeLoggingRecommendsCard> createState()=>
    _NativeLoggingRecommendsCardState();
}

class _NativeLoggingRecommendsCardState
    extends State<NativeLoggingRecommendsCard> {
  late NativeM43RecommendationAudit _audit;
  String categoryId='';

  @override
  void initState(){
    super.initState();
    _audit=NativeM43RecommendationAudit(widget.catalog);
    categoryId=_initialCategory();
  }

  String _initialCategory(){
    final current=widget.catalog.sessionActive
      ? widget.catalog.currentTask?.categoryId : null;
    if(current!=null&&widget.catalog.categories.any((c)=>c.id==current)){
      return current;
    }
    return widget.catalog.categories.firstOrNull?.id??'';
  }

  @override
  void didUpdateWidget(covariant NativeLoggingRecommendsCard old){
    super.didUpdateWidget(old);
    if(!identical(old.catalog,widget.catalog)){
      _audit=NativeM43RecommendationAudit(widget.catalog);
      if(!widget.catalog.categories.any((c)=>c.id==categoryId)){
        categoryId=_initialCategory();
      }
    }
  }

  String? _safeCover(MediaFlowTitle title) {
    final raw=title.coverUrl.trim();
    final uri=Uri.tryParse(raw);
    if(uri==null||uri.scheme!='https'||uri.host.isEmpty||
      uri.userInfo.isNotEmpty){return null;}
    return raw;
  }

  @override
  Widget build(BuildContext context){
    final theme=Theme.of(context);
    final result=NativeLoggingRecommendation.forCategory(
      widget.catalog,categoryId,audit:_audit);
    final title=result.title;
    final already=title!=null&&widget.selectedIds.contains(title.id);
    final cover=title==null?null:_safeCover(title);
    return Card(
      key:const Key('logging-recommends-card'),
      child:Padding(padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[
            Icon(Icons.auto_awesome_outlined,
              color:theme.colorScheme.primary),
            const SizedBox(width:8),
            const Expanded(child:Text('MEDIAFLOW RECOMMENDS',
              key:Key('logging-recommends-heading'),
              style:TextStyle(fontWeight:FontWeight.w700))),
          ]),
          const SizedBox(height:8),
          DropdownButtonFormField<String>(
            key:const Key('logging-recommends-category'),
            isExpanded:true,
            initialValue:categoryId.isEmpty?null:categoryId,
            decoration:const InputDecoration(
              border:OutlineInputBorder(),labelText:'Recommendation category',
              isDense:true),
            items:[
              for(final category in widget.catalog.categories)
                DropdownMenuItem<String>(
                  value:category.id,
                  child:Text(category.name,
                    overflow:TextOverflow.ellipsis)),
            ],
            onChanged:(id){
              if(id!=null){setState(()=>categoryId=id);}
            },
          ),
          const SizedBox(height:8),
          if(title!=null)...[
            Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Container(
                width:62,height:85,clipBehavior:Clip.antiAlias,
                decoration:BoxDecoration(
                  borderRadius:BorderRadius.circular(8),
                  color:theme.colorScheme.surfaceContainerHighest),
                child:cover==null
                  ?const Icon(Icons.movie_outlined,size:27)
                  :Image.network(cover,fit:BoxFit.cover,
                    errorBuilder:(_,error,stack)=>
                      const Icon(Icons.movie_outlined,size:27)),
              ),
              const SizedBox(width:11),
              Expanded(child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(title.title,
                    key:const Key('logging-recommends-title'),
                    style:theme.textTheme.titleMedium,
                    maxLines:3,overflow:TextOverflow.ellipsis),
                  const SizedBox(height:4),
                  Text('${title.progress.toStringAsFixed(0)} / '
                      '${title.total?.toStringAsFixed(0)??"?"} · '
                      '${title.status} · ${title.priority}',
                    maxLines:2,overflow:TextOverflow.ellipsis),
                  if(result.source==NativeLoggingRecommendSource.savedTask)
                    const Text('Current saved task',
                      key:Key('logging-recommends-saved-source')),
                  if(result.source==
                      NativeLoggingRecommendSource.personalOrderPreview)
                    Text('Queue preview #${result.queuePosition}'
                      '${result.fromCollection?" · Collection":""}',
                      key:const Key('logging-recommends-queue-source')),
                ],
              )),
            ]),
            const SizedBox(height:8),
          ],
          Text(result.message,key:const Key('logging-recommends-evidence'),
            style:theme.textTheme.bodySmall),
          const SizedBox(height:8),
          Wrap(spacing:8,runSpacing:7,children:[
            FilledButton.tonalIcon(
              key:const Key('logging-use-recommended-title'),
              onPressed:result.canUse?()=>widget.onUse(title!):null,
              icon:Icon(already?Icons.check_circle_outline:
                Icons.playlist_add_outlined),
              label:Text(already?'Review added title':'Use recommended title'),
            ),
            if(already)
              const Text('Selected locally · not submitted',
                key:Key('logging-recommends-selected')),
          ]),
          const SizedBox(height:4),
          Text('Like MediaFlow v478 Logging: adds an exact title to '
            'your workspace. Native logs remain local previews; '
            'History, XP and cloud writes are disabled.',
            style:theme.textTheme.bodySmall),
        ])),
    );
  }
}
