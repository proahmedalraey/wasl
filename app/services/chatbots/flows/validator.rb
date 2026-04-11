require 'set'

class Chatbots::Flows::Validator
  Result = Struct.new(:valid?, :errors, keyword_init: true)

  SUPPORTED_NODE_TYPES = %w[
    start
    send_message
    message
    ask_input
    input
    set_variable
    condition
    handoff
    resolve
    end
  ].freeze
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
    errors << 'meta must be an object when provided' if definition.key?('meta') && !definition['meta'].is_a?(Hash)
    errors << 'triggers must be an array when provided' if definition.key?('triggers') && !definition['triggers'].is_a?(Array)
    if definition.key?('variables_schema') && !definition['variables_schema'].is_a?(Hash)
      errors << 'variables_schema must be an object when provided'
    end
  end

  def validate_nodes
    ids = []

    nodes.each_with_index do |node, index|
      unless node.is_a?(Hash)
        errors << "Node #{index + 1} must be an object"
        next
      end

      node_id = node['id'] || node[:id]
      node_type_value = node_type(node)
      node_data = node['data'] || node[:data]

      if node_id.blank?
        errors << "Node #{index + 1} is missing id"
      elsif !node_id.is_a?(String)
        errors << "Node #{index + 1} id must be a string"
      else
        ids << node_id
      end

      if node_type_value.blank?
        errors << "Node #{node_label(index, node)} is missing type"
      elsif !node_type_value.is_a?(String)
        errors << "Node #{node_label(index, node)} type must be a string"
      elsif !SUPPORTED_NODE_TYPES.include?(node_type_value)
        errors << "Node #{node_label(index, node)} has unsupported type '#{node_type_value}'"
      end

      next unless node_type_value.present? && SUPPORTED_NODE_TYPES.include?(node_type_value)

      if %w[send_message message].include?(node_type_value)
        unless node_data.is_a?(Hash)
          errors << "Node #{node_label(index, node)} (#{node_type_value}) must have a data object"
          next
        end
        text = node_data['text'] || node_data[:text]
        errors << "Node #{node_label(index, node)} (#{node_type_value}) data.text must be a non-empty string" unless text.is_a?(String) && text.present?
      end

      if %w[ask_input input].include?(node_type_value)
        unless node_data.is_a?(Hash)
          errors << "Node #{node_label(index, node)} (#{node_type_value}) must have a data object"
          next
        end
        variable_key = node_data['variable_key'] || node_data[:variable_key]
        prompt = node_data['prompt'] || node_data[:prompt]
        if variable_key.present? && !variable_key.is_a?(String)
          errors << "Node #{node_label(index, node)} (#{node_type_value}) data.variable_key must be a string when provided"
        end
        if prompt.present? && !prompt.is_a?(String)
          errors << "Node #{node_label(index, node)} (#{node_type_value}) data.prompt must be a string when provided"
        end
      end

      if node_type_value == 'set_variable'
        unless node_data.is_a?(Hash)
          errors << "Node #{node_label(index, node)} (set_variable) must have a data object"
          next
        end
        key = node_data['key'] || node_data[:key]
        errors << "Node #{node_label(index, node)} (set_variable) data.key is required" unless key.is_a?(String) && key.present?
      end
    end

    errors << 'Each node must have a unique id' if ids.uniq.length != ids.length
  end

  def validate_edges
    edges.each_with_index do |edge, index|
      unless edge.is_a?(Hash)
        errors << "Edge #{index + 1} must be an object"
        next
      end

      source = edge['source'] || edge[:source]
      target = edge['target'] || edge[:target]
      errors << "Edge #{index + 1} is missing source" if source.blank?
      errors << "Edge #{index + 1} is missing target" if target.blank?
      errors << "Edge #{index + 1} source must be a string" if source.present? && !source.is_a?(String)
      errors << "Edge #{index + 1} target must be a string" if target.present? && !target.is_a?(String)
      errors << "Edge source node not found: #{source}" if source.present? && !node_ids.include?(source)
      errors << "Edge target node not found: #{target}" if target.present? && !node_ids.include?(target)

      condition = edge['condition'] || edge[:condition]
      next if condition.blank?

      unless condition.is_a?(Hash)
        errors << "Edge #{index + 1} condition must be an object when provided"
        next
      end

      operator = condition['operator'] || condition[:operator]
      key = condition['key'] || condition[:key]
      errors << "Edge #{index + 1} condition.operator is required" if operator.blank?
      errors << "Edge #{index + 1} condition.key is required" if key.blank?
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
    return if terminal_nodes.blank?

    reachable = reachable_nodes(start_node_id)
    return if terminal_nodes.any? { |node| reachable.include?(node['id'] || node[:id]) }

    errors << 'Flow must have a reachable terminal path from start node'
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
    @node_ids ||= nodes.filter_map do |node|
      next unless node.is_a?(Hash)

      node['id'] || node[:id]
    end
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

  def node_label(index, node)
    node_id = node['id'] || node[:id]
    node_id.present? ? "'#{node_id}'" : index + 1
  end
end
