class ChatbotSessionEvent < ApplicationRecord
  self.record_timestamps = false

  belongs_to :chatbot_session

  enum event_type: {
    node_entered: 0,
    node_executed: 1,
    transition_taken: 2,
    error: 3
  }

  validates :payload, jsonb_attributes_length: true
end
