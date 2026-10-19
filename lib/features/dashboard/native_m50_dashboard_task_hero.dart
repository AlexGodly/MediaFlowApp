import 'package:flutter/material.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_m50_task_display.dart';

/// Snapshot-only v410-style next-task presentation. Every action navigates
/// to an existing screen; no task, reroll, History, XP or cloud writes.
class NativeM50DashboardTaskHero extends StatelessWidget {
  const NativeM50DashboardTaskHero({
    super.key,required this.catalog,required this.openLibrary,
    this.openPersonalOrder,this.onReviewTaskInLogging,
  });
  final MediaFlowCatalog catalog;
  final VoidCallback openLibrary;
  final VoidCallback? openPersonalOrder;
  final ValueChanged<MediaFlowCatalog>? onReviewTaskInLogging;

  static String _amount(double value) => value.isFinite
    ?(value==value.roundToDouble()
      ?value.toInt().toString():value.toStringAsFixed(1)):'Unknown';

  Widget _poster(BuildContext context,NativeM50TaskDisplay data,
      {required bool compact}) {
    final color=Theme.of(context).colorScheme;
    final placeholder=ColoredBox(
      color:color.surfaceContainerHighest,
      child:Center(child:Icon(Icons.movie_creation_outlined,
        size:compact?32:44,color:color.onSurfaceVariant)),
    );
    final url=data.safeCoverUrl;
    return Semantics(label:url==null?'Task poster unavailable':'Task poster',
      child:Container(
        key:const Key('m50-task-poster'),
        width:compact?98:142,height:compact?134:204,
        clipBehavior:Clip.antiAlias,
        decoration:BoxDecoration(borderRadius:BorderRadius.circular(14),
          border:Border.all(color:color.outlineVariant)),
        child:url==null?placeholder:Image.network(url,fit:BoxFit.cover,
          errorBuilder:(_,error,stack)=>placeholder),
      ),
    );
  }

  Widget _tag(BuildContext context,String label,IconData icon) {
    final colors=Theme.of(context).colorScheme;
    return Container(
      padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),
      decoration:BoxDecoration(
        color:colors.primary.withValues(alpha:0.09),
        borderRadius:BorderRadius.circular(16),
        border:Border.all(color:colors.outlineVariant)),
      child:Row(mainAxisSize:MainAxisSize.min,children:[
        Icon(icon,size:14,color:colors.primary),
        const SizedBox(width:5),
        Text(label,style:Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }

  Widget _actions(NativeM50TaskDisplay display)=>Wrap(spacing:8,runSpacing:8,children:[
    if(onReviewTaskInLogging!=null && display.active)
      FilledButton.tonalIcon(
        key:const Key('m51-review-in-logging'),
        onPressed:display.resolution==NativeM50TitleResolution.exact
          ?()=>onReviewTaskInLogging!(catalog):null,
        icon:const Icon(Icons.playlist_add_check_outlined),
        label:const Text('Review in Logging')),
    OutlinedButton.icon(key:const Key('m50-browse-library'),
      onPressed:openLibrary,icon:const Icon(Icons.local_library_outlined),
      label:const Text('Browse Library')),
    if(openPersonalOrder!=null)OutlinedButton.icon(
      key:const Key('m50-open-personal-order'),
      onPressed:openPersonalOrder,
      icon:const Icon(Icons.format_list_numbered_outlined),
      label:const Text('Personal Order')),
  ]);

  Widget _summary(BuildContext context,NativeM50TaskDisplay data,
      {required bool compact}) {
    final task=data.task,theme=Theme.of(context);
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        Expanded(child:Text('NEXT TASK',
          key:const Key('m50-hero-heading'),
          style:theme.textTheme.labelLarge?.copyWith(
            fontWeight:FontWeight.w700,letterSpacing:0.8))),
        if(task!=null)_tag(context,'Saved task',Icons.visibility_outlined),
      ]),
      const SizedBox(height:10),
      Row(children:[
        if(data.category?.icon.isNotEmpty==true)...[
          Text(data.category!.icon,key:const Key('m50-category-icon'),
            style:const TextStyle(fontSize:22)),
          const SizedBox(width:8),
        ],
        Expanded(child:Text(data.categoryName,
          key:const Key('m50-task-category'),
          maxLines:2,overflow:TextOverflow.ellipsis,
          style:compact?theme.textTheme.titleLarge:
            theme.textTheme.headlineSmall)),
      ]),
      if(task==null)...[
        const SizedBox(height:9),
        Text('No active task',style:theme.textTheme.titleLarge),
        Text(data.resolutionNote,key:const Key('m50-task-resolution')),
      ]else...[
        const SizedBox(height:12),
        Text('Recommended title',
          style:theme.textTheme.labelMedium),
        Text(data.recommendedName,
          key:const Key('m50-recommendation-title'),
          maxLines:3,overflow:TextOverflow.ellipsis,
          style:theme.textTheme.titleLarge),
        const SizedBox(height:7),
        Text('Target: ${_amount(task.low)}–${_amount(task.high)} '
          '${task.unit}',
          key:const Key('m50-task-target'),
          style:theme.textTheme.titleMedium),
        const SizedBox(height:6),
        Text(task.libraryId.isNotEmpty
          ?'Saved exact Library ID: ${task.libraryId}'
          :'Saved exact Library ID unavailable; title text alone '
            'cannot confirm recommendation source.',
          key:const Key('m49-task-id-label'),
          maxLines:3,overflow:TextOverflow.ellipsis,
          style:theme.textTheme.bodySmall),
        if(data.resolution!=NativeM50TitleResolution.exact)...[
          const SizedBox(height:4),
          Text(data.resolutionNote,key:const Key('m50-task-resolution'),
            style:theme.textTheme.bodySmall),
        ],
        const SizedBox(height:5),
        Text(data.sourceClaim,key:const Key('m50-task-source-claim'),
          style:theme.textTheme.bodySmall),
      ],
    ]);
  }

  Widget _metadata(BuildContext context,NativeM50TaskDisplay data) {
    final item=data.title,task=data.task;
    if(task==null)return const SizedBox.shrink();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(item!=null)...[
        const SizedBox(height:10),
        Wrap(spacing:6,runSpacing:6,children:[
          _tag(context,item.status.isEmpty?'Unknown':item.status,
            Icons.bookmark_outline),
          if(item.priority.isNotEmpty)
            _tag(context,'${item.priority} priority',Icons.flag_outlined),
        ]),
        if(data.progressPercent!=null)...[
          const SizedBox(height:12),
          Row(children:[
            Expanded(child:Text('Library progress',
              style:Theme.of(context).textTheme.bodyMedium)),
            Text('${_amount(item.progress)} / ${_amount(item.total!)}',
              key:const Key('m50-progress-label'),
              style:Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height:5),
          Semantics(
            label:'Library progress: '
              '${(data.progressPercent!*100).round()} percent',
            child:LinearProgressIndicator(
              key:const Key('m50-task-progress'),
              value:data.progressPercent,minHeight:7,
              borderRadius:BorderRadius.circular(8))),
        ],
      ],
      if(task.reasons.isNotEmpty)...[
        const SizedBox(height:12),
        Text('Task reasons',
          style:Theme.of(context).textTheme.labelLarge),
        const SizedBox(height:5),
        for(final reason in task.reasons.take(4))
          Padding(padding:const EdgeInsets.only(bottom:4),
            child:Text('• $reason',
              key:const Key('m50-task-reason'),softWrap:true)),
        if(task.reasons.length>4)
          Text('+${task.reasons.length-4} more reasons',
            style:Theme.of(context).textTheme.bodySmall),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context){
    final data=NativeM50TaskDisplay.fromCatalog(catalog);
    return Card(key:const Key('m50-task-hero'),
      child:LayoutBuilder(builder:(context,bounds){
        // Layout against the actual card width, not screen width.
        final wide=bounds.maxWidth>=620;
        final padding=bounds.maxWidth<430?14.0:20.0;
        final body=Column(crossAxisAlignment:CrossAxisAlignment.stretch,
          children:[
            _summary(context,data,compact:!wide),
            _metadata(context,data),
            const SizedBox(height:12),
            _actions(data),
            const SizedBox(height:8),
            Text('Read-only snapshot · Live task actions remain on '
              'the original MediaFlow website.',
              key:const Key('m50-readonly-note'),
              style:Theme.of(context).textTheme.bodySmall),
          ]);
        return Padding(padding:EdgeInsets.all(padding),
          child:data.task==null?body:wide
            ?Row(key:const Key('m50-wide-layout'),
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                _poster(context,data,compact:false),
                const SizedBox(width:18),
                Expanded(child:body),
              ])
            :Column(key:const Key('m50-compact-layout'),
              crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  _poster(context,data,compact:true),
                  const SizedBox(width:12),
                  Expanded(child:Column(
                    crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Text('SAVED TASK',
                        style:Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height:7),
                      Text(data.categoryName,maxLines:3,
                        overflow:TextOverflow.ellipsis,
                        style:Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height:7),
                      Text(data.recommendedName,maxLines:4,
                        overflow:TextOverflow.ellipsis),
                    ])),
                ]),
                const SizedBox(height:14),
                body,
              ]),
        );
      }),
    );
  }
}
