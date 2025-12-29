class GraphData {
  final List<String> labels;
  final List<num> meters;
  final List<num> salary;

  const GraphData({
    required this.labels,
    required this.meters,
    required this.salary,
  });

  factory GraphData.fromJson(Map<String, dynamic> json) {
    final graph = (json['graph_data'] as Map).cast<String, dynamic>();
    return GraphData(
      labels: (graph['labels'] as List? ?? const []).map((e) => e.toString()).toList(growable: false),
      meters: (graph['meters'] as List? ?? const []).map((e) => e as num).toList(growable: false),
      salary: (graph['salary'] as List? ?? const []).map((e) => e as num).toList(growable: false),
    );
  }
}
