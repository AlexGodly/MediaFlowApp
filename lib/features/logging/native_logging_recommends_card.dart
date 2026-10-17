import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_logging_recommends.dart';
import '../../services/native_m43_recommendation_audit.dart';

enum NativeRecommendationSelectionFilter { notAdded, all, alreadyAdded }

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
  List<NativeLoggingRecommendation>? _queueCandidates;
  NativeRecommendationSelectionFilter _queueFilter=
    NativeRecommendationSelectionFilter.notAdded;
  String _queueQuery='';
  int _queuePage=0;
  static const int _queuePageSize=5;

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
      showQueue=false;
      _queueCandidates=null;
      _queuePage=0;
      _queueQuery='';
      _queueFilter=NativeRecommendationSelectionFilter.notAdded;
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
    // Calculate queue evidence only after expansion and only once for
    // this account snapshot/category, even when selections change. Never
    // scan a 100k-title Library again for each checkbox interaction.
    if(showQueue){
      _queueCandidates??=NativeLoggingRecommendation.browseQueueCatalog(
        widget.catalog,categoryId,audit:_audit,maxCandidates:500);
    }
    final needle=_queueQuery.trim().toLowerCase();
    final filtered=showQueue
      ? (_queueCandidates??const <NativeLoggingRecommendation>[])
          .where((entry){
            final isAdded=widget.selectedIds.contains(entry.title!.id);
            final matchesFilter=switch(_queueFilter){
              NativeRecommendationSelectionFilter.notAdded=>!isAdded,
              NativeRecommendationSelectionFilter.all=>true,
              NativeRecommendationSelectionFilter.alreadyAdded=>isAdded,
            };
            return matchesFilter&&(needle.isEmpty||
              entry.title!.title.toLowerCase().contains(needle)||
              entry.title!.id.toLowerCase().contains(needle));
          }).toList(growable:false)
      : const <NativeLoggingRecommendation>[];
    final pages=filtered.isEmpty
      ?1:(filtered.length+_queuePageSize-1)~/_queuePageSize;
    final page=_queuePage.clamp(0,pages-1).toInt();
    final suggestions=filtered
      .skip(page*_queuePageSize).take(_queuePageSize)
      .toList(growable:false);
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
                showQueue=false;
                _queueCandidates=null;
                _queuePage=0;
                _queueQuery='';
                _queueFilter=NativeRecommendationSelectionFilter.notAdded;
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
          const SizedBox(height:8),
          if(widget.catalog.prioritizePersonalOrder==true)
            OutlinedButton.icon(
              key:const Key('logging-browse-queue'),
              onPressed:()=>setState((){
                showQueue=!showQueue;
                _queuePage=0;
              }),
              icon:Icon(showQueue?Icons.expand_less:Icons.format_list_bulleted),
              label:Text(showQueue?'Hide queue suggestions':
                'Browse more recommendations'),
            ),
          if(showQueue)...[
            const SizedBox(height:6),
            const Text('More from Personal Order',
              key:Key('logging-queue-heading'),
              style:TextStyle(fontWeight:FontWeight.w600)),
            const Text('Queue previews, not live task rerolls. '
              'Selecting one never changes the saved task, History or XP.',
              key:Key('logging-queue-disclaimer')),
            const SizedBox(height:8),
            TextField(
              key:const Key('logging-queue-search'),
              onChanged:(value)=>setState((){
                _queueQuery=value;
                _queuePage=0;
              }),
              decoration:const InputDecoration(
                labelText:'Search queue titles or Library IDs',
                prefixIcon:Icon(Icons.search),
                isDense:true,border:OutlineInputBorder(),
              ),
            ),
            const SizedBox(height:7),
            Wrap(spacing:6,runSpacing:5,children:[
              for(final option in NativeRecommendationSelectionFilter.values)
                ChoiceChip(
                  key:ValueKey('logging-queue-filter-${option.name}'),
                  selected:_queueFilter==option,
                  label:Text(switch(option){
                    NativeRecommendationSelectionFilter.notAdded=>'Not added',
                    NativeRecommendationSelectionFilter.all=>'All',
                    NativeRecommendationSelectionFilter.alreadyAdded=>'Already added',
                  }),
                  onSelected:(_)=>setState((){
                    _queueFilter=option;
                    _queuePage=0;
                  }),
                ),
            ]),
            const SizedBox(height:5),
            Text('Showing ${suggestions.length} of ${filtered.length} '
              'matching verified queue previews · page ${page+1}/$pages',
              key:const Key('logging-queue-count'),
              style:theme.textTheme.bodySmall),
            if((_queueCandidates?.length??0)>=500)
              const Text('Showing only the first 500 verified queue '
                'candidates; later entries are not checked in this beta.',
                key:Key('logging-queue-limit-note')),
            if(suggestions.isEmpty)
              const Padding(
                padding:EdgeInsets.symmetric(vertical:10),
                child:Text('No additional verified, unselected queue '
                  'titles are available for this category.',
                  key:Key('logging-queue-empty')),
              ),
            for(final suggestion in suggestions)
              Padding(
                key:ValueKey('logging-queue-row-${suggestion.title!.id}'),
                padding:const EdgeInsets.symmetric(vertical:3),
                child:DecoratedBox(
                  decoration:BoxDecoration(
                    color:theme.colorScheme.surfaceContainerLow,
                    borderRadius:BorderRadius.circular(10)),
                  child:Padding(
                    padding:const EdgeInsets.fromLTRB(10,8,7,8),
                    child:Row(children:[
                      Expanded(child:Column(
                        crossAxisAlignment:CrossAxisAlignment.start,
                        children:[
                          Text(suggestion.title!.title,
                            maxLines:2,overflow:TextOverflow.ellipsis,
                            style:theme.textTheme.bodyMedium),
                          Text('Queue #${suggestion.queuePosition}'
                            '${suggestion.fromCollection?" · Collection":""}'
                            ' · ${suggestion.title!.status}',
                            maxLines:2,overflow:TextOverflow.ellipsis,
                            style:theme.textTheme.bodySmall),
                        ],
                      )),
                      const SizedBox(width:6),
                      IconButton(
                        key:ValueKey('logging-use-queue-${suggestion.title!.id}'),
                        tooltip:widget.selectedIds.contains(
                          suggestion.title!.id)
                          ?'Review ${suggestion.title!.title} in Logging'
                          :'Use ${suggestion.title!.title} in Logging',
                        onPressed:()=>widget.onUse(suggestion.title!),
                        icon:Icon(widget.selectedIds.contains(
                          suggestion.title!.id)
                          ?Icons.check_circle_outline
                          :Icons.playlist_add_outlined),
                      ),
                    ]),
                  ),
                ),
              ),
            if(pages>1)
              Row(children:[
                IconButton(
                  key:const Key('logging-queue-previous-page'),
                  onPressed:page>0?()=>setState(()=>_queuePage=page-1):null,
                  icon:const Icon(Icons.chevron_left),
                  tooltip:'Previous queue page'),
                Expanded(child:Text('Page ${page+1} of $pages',
                  key:const Key('logging-queue-page-label'),
                  textAlign:TextAlign.center)),
                IconButton(
                  key:const Key('logging-queue-next-page'),
                  onPressed:page+1<pages
                    ?()=>setState(()=>_queuePage=page+1):null,
                  icon:const Icon(Icons.chevron_right),
                  tooltip:'Next queue page'),
              ]),
          ],
          const SizedBox(height:4),
          Text('Like MediaFlow v478 Logging: adds an exact title to 
            'your workspace. Native logs remain local previews; '
            'History, XP and cloud writes are disabled.',
            style:theme.textTheme.bodySmall),
        ])),
    );
  }
}
