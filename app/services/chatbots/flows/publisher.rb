require 'digest'

class Chatbots::Flows::Publisher
  pattr_initialize [:chatbot_flow!, :actor]

  def perform
    version_number = (chatbot_flow.flow_versions.maximum(:version) || 0) + 1
    checksum = Digest::SHA256.hexdigest(chatbot_flow.draft_definition.to_json)

    version = chatbot_flow.flow_versions.create!(
      version: version_number,
      definition: chatbot_flow.draft_definition,
      checksum: checksum,
      created_by_id: actor&.id,
      published_at: Time.current
    )

    chatbot_flow.update!(
      status: :published,
      published_version: version,
      updated_by_id: actor&.id
    )

    version
  end
end
