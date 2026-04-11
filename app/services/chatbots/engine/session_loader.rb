class Chatbots::Engine::SessionLoader
  pattr_initialize [:agent_bot!, :conversation!, :message!]

  def perform
    flow = agent_bot.chatbot_flow
    return if flow.blank? || flow.published_version.blank?

    ChatbotSession.transaction do
      session = ChatbotSession.lock
                             .find_by(conversation_id: conversation.id, status: :active)

      session ||= ChatbotSession.create!(
        account_id: conversation.account_id,
        conversation_id: conversation.id,
        chatbot_flow_version: flow.published_version,
        status: :active,
        current_node_id: start_node_id(flow.published_version.definition)
      )

      return if session.last_input_message_id == message.id

      session.update!(last_input_message_id: message.id)
      session
    end
  end

  private

  def start_node_id(definition)
    nodes = definition['nodes'] || []
    start_node = nodes.find { |node| (node['type'] || node[:type]) == 'start' }
    start_node&.dig('id') || start_node&.dig(:id)
  end
end
