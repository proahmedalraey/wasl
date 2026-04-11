class ChatbotSession < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :chatbot_flow_version

  has_many :chatbot_session_events, dependent: :destroy_async

  enum status: { active: 0, completed: 1, handoff: 2, failed: 3 }

  validates :variables, jsonb_attributes_length: true
  validates :context, jsonb_attributes_length: true
end
