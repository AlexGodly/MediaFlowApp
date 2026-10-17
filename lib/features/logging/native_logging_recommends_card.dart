import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_logging_recommends.dart';
import '../../services/native_logging_recommend_queue.dart';
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
  bool showQueue=false;
  int queueOffset=0;

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
      queueOffset=0;
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

  Widget _queueBrowser(BuildContext context){
    final page=NativeLoggingRecommendQueue.page(widget.catalog,categoryId,
      offset:queueOffset,audit:_audit);
    final theme=Theme.of(context);
    return Container(
      key:const Key('logging-queue-browser'),
      padding:const EdgeInsets.all(10),
      decoration:BoxDecoration(
        color:theme.colorScheme.surfaceContainerLow,
        borderRadius:BorderRadius.circular(12),
        border:Border.all(color:theme.colorScheme.outlineVariant)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('PERSONAL ORDER QUEUE · PREVIEW ONLY',
          style:theme.textTheme.labelMedium?.copyWith(
            fontWeight:FontWeight.w700)),
        const SizedBox(height:5),
        Text(page.message,key:const Key('logging-queue-disclaimer'),
          style:theme.textTheme.bodySmall),
        if(page.items.isEmpty)...[
          const SizedBox(height:8),
          Text('No verified selectable queue titles on this page.',
            key:const Key('logging-queue-empty'),
            style:theme.textTheme.bodyMedium),
        ],
        for(final entry in page.items)...[
          const SizedBox(height:8),
          Row(key:ValueKey('logging-queue-row-${entry.rank}'),
            crossAxisAlignment:CrossAxisAlignment.center,children:[
            SizedBox(width:34,child:Text('#${entry.rank}',
              style:theme.textTheme.labelMedium)),
            Expanded(child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(entry.title.title,
                  maxLines:2,overflow:TextOverflow.ellipsis,
                  style:theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:FontWeight.w600)),
                Text(entry.fromCollection
                    ?'Collection queue · ${entry.title.status}'
                    :'Direct title · ${entry.title.status}',
                  maxLines:1,overflow:TextOverflow.ellipsis,
                  style:theme.textTheme.bodySmall),
              ])),
            IconButton(
              key:ValueKey('logging-queue-use-${entry.rank}'),
              tooltip:widget.selectedIds.contains(entry.title.id)
                ?'Review already selected title'
                :'Use queue title in Logging',
              icon:Icon(widget.selectedIds.contains(entry.title.id)
                ?Icons.check_outlined:Icons.playlist_add_outlined),
              onPressed:()=>widget.onUse(entry.title)),
          ]),
        ],
        if(page.offset>0||page.hasMore)...[
          const SizedBox(height:8),
          Row(children:[
            IconButton(
              key:const Key('logging-queue-previous'),
              tooltip:'Previous recommendations',
              onPressed:page.offset==0?null:()=>setState(
                ()=>queueOffset-=NativeLoggingRecommendQueue.pageSize),
              icon:const Icon(Icons.chevron_left)),
            Expanded(child:Text(
              'Queue positions ${page.offset+1}–'
              '${page.offset+NativeLoggingRecommendQueue.pageSize}',
              textAlign:TextAlign.center,
              style:theme.textTheme.bodySmall)),
            IconButton(
              key:const Key('logging-queue-next'),
              tooltip:'Next recommendations',
              onPressed:page.hasMore?()=>setState(
                ()=>queueOffset+=NativeLoggingRecommendQueue.pageSize):null,
              icon:const Icon(Icons.chevron_right)),
          ]),
        ],
        const SizedBox(height:5),
        Text('Browsing does not reroll the task or advance '
          'Collection traversal. Up to 50 queue positions can be reviewed.',
          style:theme.textTheme.bodySmall),
      ]),
    );
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
              if(id!=null){setState((){
                categoryId=id;
                queueOffset=0;
              });}
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
          const SizedBox(height:9),
          OutlinedButton.icon(
            key:const Key('logging-browse-recommendation-queue'),
            onPressed:()=>setState((){
              showQueue=!showQueue;
              queueOffset=0;
            }),
            icon:Icon(showQueue
              ?Icons.expand_less:Icons.view_list_outlined),
            label:Text(showQueue
              ?'Hide Personal Order queue'
              :'Browse Personal Order recommendations'),
          ),
          if(showQueue)...[
            const SizedBox(height:9),
            _queueBrowser(context),
          ],
          const SizedBox(height:4),
          Text('Like MediaFlow v478 Logging: adds an exact title to '
            'your workspace. Native logs remain local previews; '
            'History, XP and cloud writes are disabled.',
            style:theme.textTheme.bodySmall),
        ])),
    );
  }
}
