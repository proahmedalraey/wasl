class ChatbotFlow < ApplicationRecord
  belongs_to :account
  belongs_to :agent_bot
  belongs_to :published_version, class_name: 'ChatbotFlowVersion', optional: true

  has_many :flow_versions, class_name: 'ChatbotFlowVersion', dependent: :destroy_async, inverse_of: :chatbot_flow

  enum status: { draft: 0, published: 1, archived: 2 }

  validates :name, presence: true
  validates :draft_definition, jsonb_attributes_length: true

  def published_definition
    published_version&.definition || {}
  end
end
