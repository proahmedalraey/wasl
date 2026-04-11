class Chatbots::Engine::EntryPoint
  pattr_initialize [:agent_bot!, :message!, :event_name!]

  def perform
    return unless processable_message?
    return unless message.conversation.pending?

    session = Chatbots::Engine::SessionLoader.new(
      agent_bot: agent_bot,
      conversation: message.conversation,
      message: message
    ).perform
    return if session.blank?

    Chatbots::Engine::NodeExecutor.new(agent_bot: agent_bot, session: session, message: message).perform
  end

  private

  def processable_message?
    return false if message.private?
    return true if message.incoming?

    event_name == 'message_updated' && message.outgoing? && message.content_type == 'input_select'
  end
end
