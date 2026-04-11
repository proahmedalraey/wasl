class Chatbots::Engine::TransitionResolver
  pattr_initialize [:definition!, :session!, :current_node!]

  def next_node_id
    outgoing_edges.each do |edge|
      condition = edge['condition'] || edge[:condition]
      return edge_target(edge) if condition.blank? || evaluate_condition(condition)
    end

    nil
  end

  private

  def outgoing_edges
    (definition['edges'] || []).select { |edge| edge_source(edge) == node_id(current_node) }
  end

  def evaluate_condition(condition)
    operator = condition['operator'] || condition[:operator]
    key = condition['key'] || condition[:key]
    value = condition['value'] || condition[:value]
    current_value = session.variables[key]

    case operator
    when 'eq'
      current_value.to_s == value.to_s
    when 'not_eq'
      current_value.to_s != value.to_s
    when 'present'
      current_value.present?
    when 'blank'
      current_value.blank?
    else
      false
    end
  end

  def edge_source(edge)
    edge['source'] || edge[:source]
  end

  def edge_target(edge)
    edge['target'] || edge[:target]
  end

  def node_id(node)
    node['id'] || node[:id]
  end
end
