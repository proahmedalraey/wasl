class Chatbots::Engine::NodeExecutor
  MAX_EXECUTION_STEPS = 20

  pattr_initialize [:agent_bot!, :session!, :message!]

  def perform
    definition = session.chatbot_flow_version.definition
    capture_waiting_input! if awaiting_input?

    safety_counter = 0
    while session.active? && session.current_node_id.present? && safety_counter < MAX_EXECUTION_STEPS
      safety_counter += 1
      node = node_by_id(definition, session.current_node_id)
      break if node.blank?

      track_event(:node_entered, node, message_id: message.id)
      execute_node(node)
      break unless auto_advance?(node)

      next_id = next_node_id(definition, node)
      track_event(:transition_taken, node, to: next_id) if next_id.present?
      session.update!(current_node_id: next_id)
    end
  rescue StandardError => e
    track_event(:error, { 'id' => session.current_node_id, 'type' => 'unknown' }, error: e.message)
    session.failed!
    raise
  end

  private

  def capture_waiting_input!
    key = session.context['awaiting_input_for']
    return if key.blank? || !message.incoming?

    session.variables[key] = message.content
    session.context.delete('awaiting_input_for')
    session.save!

    current_node = node_by_id(session.chatbot_flow_version.definition, session.current_node_id)
    next_id = next_node_id(session.chatbot_flow_version.definition, current_node)
    session.update!(current_node_id: next_id)
  end

  def awaiting_input?
    session.context['awaiting_input_for'].present?
  end

  def execute_node(node)
    node_type = node['type'] || node[:type]
    data = node['data'] || node[:data] || {}

    case node_type
    when 'start', 'condition', 'set_variable'
      set_variable(data) if node_type == 'set_variable'
      track_event(:node_executed, node, action: node_type)
    when 'send_message', 'message'
      send_message(data['text'])
      track_event(:node_executed, node, action: 'send_message')
    when 'ask_input', 'input'
      prompt = data['prompt']
      key = data['variable_key'] || 'response'
      send_message(prompt) if prompt.present?
      session.context['awaiting_input_for'] = key
      session.save!
      track_event(:node_executed, node, action: 'ask_input', variable_key: key)
    when 'handoff'
      session.conversation.bot_handoff!
      session.handoff!
      track_event(:node_executed, node, action: 'handoff')
    when 'resolve'
      session.conversation.resolved!
      session.completed!
      track_event(:node_executed, node, action: 'resolve')
    when 'end'
      session.completed!
      track_event(:node_executed, node, action: 'end')
    end
  end

  def auto_advance?(node)
    return false unless session.active?

    node_type = node['type'] || node[:type]
    !%w[ask_input input].include?(node_type)
  end

  def next_node_id(definition, node)
    Chatbots::Engine::TransitionResolver.new(
      definition: definition,
      session: session,
      current_node: node
    ).next_node_id
  end

  def node_by_id(definition, node_id)
    (definition['nodes'] || []).find { |node| (node['id'] || node[:id]) == node_id }
  end

  def send_message(content)
    return if content.blank?

    session.conversation.messages.create!(
      content: content,
      message_type: :outgoing,
      account_id: session.conversation.account_id,
      inbox_id: session.conversation.inbox_id,
      sender: agent_bot
    )
  end

  def set_variable(data)
    key = data['key']
    return if key.blank?

    value = data['value']
    source = data['source']
    value = message.content if source == 'message'

    session.variables[key] = value
    session.save!
    mirror_variable(key, value, data['target'])
  end

  def mirror_variable(key, value, target)
    case target
    when 'conversation'
      attrs = session.conversation.custom_attributes || {}
      attrs[key] = value
      session.conversation.update!(custom_attributes: attrs)
    when 'contact'
      attrs = session.conversation.contact.custom_attributes || {}
      attrs[key] = value
      session.conversation.contact.update!(custom_attributes: attrs)
    end
  end

  def track_event(event_type, node, payload = {})
    session.chatbot_session_events.create!(
      event_type: event_type,
      node_id: node['id'] || node[:id],
      payload: payload,
      created_at: Time.current
    )
  end
end
