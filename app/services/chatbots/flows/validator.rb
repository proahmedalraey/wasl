require 'set'

class Chatbots::Flows::Validator
  Result = Struct.new(:valid?, :errors, keyword_init: true)

  TERMINAL_NODE_TYPES = %w[end handoff resolve].freeze

  pattr_initialize [:definition!]

  def perform
    @errors = []
    validate_definition_shape
    return result if errors.present?

    validate_nodes
    validate_edges
    validate_start_node
    validate_orphan_nodes
    validate_terminal_path
    validate_cycles

    result
  end

  private

  attr_reader :errors

  def result
    Result.new(valid?: errors.empty?, errors: errors)
  end

  def validate_definition_shape
    errors << 'Definition must be a JSON object' unless definition.is_a?(Hash)
    errors << 'Nodes must be an array' unless nodes.is_a?(Array)
    errors << 'Edges must be an array' unless edges.is_a?(Array)
  end

  def validate_nodes
    ids = nodes.filter_map { |node| node['id'] || node[:id] }
    errors << 'Each node must have a unique id' if ids.uniq.length != ids.length
  end

  def validate_edges
    edges.each do |edge|
      source = edge['source'] || edge[:source]
      target = edge['target'] || edge[:target]
      errors << "Edge source node not found: #{source}" unless node_ids.include?(source)
      errors << "Edge target node not found: #{target}" unless node_ids.include?(target)
    end
  end

  def validate_start_node
    errors << 'Flow must have exactly one start node' unless start_nodes.length == 1
  end

  def validate_orphan_nodes
    return if start_nodes.blank?

    orphan_nodes = node_ids - reachable_nodes(start_node_id)
    errors << "Orphan nodes detected: #{orphan_nodes.join(', ')}" if orphan_nodes.present?
  end

  def validate_terminal_path
    return if start_nodes.blank?

    terminal_nodes = nodes.select { |node| TERMINAL_NODE_TYPES.include?(node_type(node)) }
    errors << 'Flow must have at least one terminal node (end, handoff, resolve)' if terminal_nodes.blank?
  end

  def validate_cycles
    allow_loops = definition.dig('meta', 'allow_loops') == true
    return if allow_loops
    return unless cycle_present?

    errors << 'Flow contains cycles. Set meta.allow_loops=true to allow cycles'
  end

  def cycle_present?
    visited = {}
    visiting = {}

    node_ids.any? { |node_id| dfs_cycle?(node_id, visited, visiting) }
  end

  def dfs_cycle?(node_id, visited, visiting)
    return false if visited[node_id]
    return true if visiting[node_id]

    visiting[node_id] = true
    next_nodes(node_id).any? { |next_node_id| dfs_cycle?(next_node_id, visited, visiting) }.tap do
      visiting.delete(node_id)
      visited[node_id] = true
    end
  end

  def nodes
    @nodes ||= definition['nodes'] || []
  end

  def edges
    @edges ||= definition['edges'] || []
  end

  def start_nodes
    @start_nodes ||= nodes.select { |node| node_type(node) == 'start' }
  end

  def start_node_id
    start_nodes.first&.dig('id') || start_nodes.first&.dig(:id)
  end

  def node_type(node)
    node['type'] || node[:type]
  end

  def node_ids
    @node_ids ||= nodes.filter_map { |node| node['id'] || node[:id] }
  end

  def next_nodes(node_id)
    edges.filter_map do |edge|
      source = edge['source'] || edge[:source]
      target = edge['target'] || edge[:target]
      source == node_id ? target : nil
    end
  end

  def reachable_nodes(start_id)
    visited = Set.new
    queue = [start_id]
    until queue.empty?
      current = queue.shift
      next if current.blank? || visited.include?(current)

      visited << current
      next_nodes(current).each { |next_node_id| queue << next_node_id }
    end
    visited.to_a
  end
end
