class Chatbots::ProcessMessageJob < ApplicationJob
  queue_as :chatbots_high

  retry_on ActiveRecord::StaleObjectError, wait: 2.seconds, attempts: 3

  def perform(agent_bot_id, message_id, event_name)
    agent_bot = AgentBot.find_by(id: agent_bot_id)
    message = Message.find_by(id: message_id)
    return if agent_bot.blank? || message.blank?
    return unless agent_bot.native?
    return unless agent_bot.account&.feature_enabled?('native_chatbot_builder')

    Chatbots::Engine::EntryPoint.new(
      agent_bot: agent_bot,
      message: message,
      event_name: event_name
    ).perform
  rescue StandardError => e
    Rails.logger.error "[Chatbots::ProcessMessageJob] bot_id=#{agent_bot_id} message_id=#{message_id} error=#{e.class.name}: #{e.message}"
    raise
  end
end
