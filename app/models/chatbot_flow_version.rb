class ChatbotFlowVersion < ApplicationRecord
  belongs_to :chatbot_flow
  has_many :chatbot_sessions, dependent: :destroy_async

  validates :version, presence: true
  validates :definition, jsonb_attributes_length: true
end
