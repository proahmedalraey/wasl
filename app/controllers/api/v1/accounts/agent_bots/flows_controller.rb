class Api::V1::Accounts::AgentBots::FlowsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :agent_bot
  before_action :check_authorization
  before_action :ensure_native_bot
  before_action :ensure_feature_enabled

  def show
    flow = chatbot_flow
    render json: serialized_flow(flow)
  end

  def update
    flow = chatbot_flow
    definition = flow_definition_param
    validation_result = Chatbots::Flows::Validator.new(definition: definition).perform
    return render json: { valid: false, errors: validation_result.errors }, status: :unprocessable_entity unless validation_result.valid?

    flow.update!(
      draft_definition: definition,
      name: params[:name].presence || flow.name,
      description: params[:description].presence || flow.description,
      updated_by_id: Current.user&.id
    )

    render json: serialized_flow(flow).merge(valid: true)
  end

  def validate
    validation_result = Chatbots::Flows::Validator.new(definition: flow_definition_param).perform
    render json: { valid: validation_result.valid?, errors: validation_result.errors }
  end

  def publish
    flow = chatbot_flow
    definition = effective_publish_definition(flow)
    validation_result = Chatbots::Flows::Validator.new(definition: definition).perform
    return render json: { valid: false, errors: validation_result.errors }, status: :unprocessable_entity unless validation_result.valid?

    persist_publish_definition!(flow, definition) if publish_definition_param_present?
    version = Chatbots::Flows::Publisher.new(chatbot_flow: flow, actor: Current.user).perform
    render json: serialized_flow(flow.reload).merge(published_version: serialized_version(version))
  end

  private

  def agent_bot
    @agent_bot ||= Current.account.agent_bots.find(params[:agent_bot_id])
  end

  def ensure_native_bot
    return if @agent_bot.native?

    render json: { error: 'Flow builder is available only for native bot type' }, status: :unprocessable_entity
  end

  def ensure_feature_enabled
    return if native_chatbot_builder_enabled?

    render json: {
      error: 'Feature not enabled',
      feature: 'native_chatbot_builder',
      account_feature_enabled: Current.account.feature_enabled?('native_chatbot_builder'),
      globally_enabled: native_chatbot_builder_globally_enabled?
    }, status: :forbidden
  end

  def chatbot_flow
    @chatbot_flow ||= @agent_bot.chatbot_flow || @agent_bot.create_chatbot_flow!(
      account_id: @agent_bot.account_id,
      name: "#{@agent_bot.name} Flow",
      status: :draft,
      created_by_id: Current.user&.id,
      updated_by_id: Current.user&.id
    )
  end

  def flow_definition_param
    definition = params[:definition]
    return definition.to_unsafe_h if definition.is_a?(ActionController::Parameters)
    return definition if definition.is_a?(Hash)

    {}
  end

  def publish_definition_param_present?
    params.key?(:definition) || params.key?('definition')
  end

  def effective_publish_definition(flow)
    publish_definition_param_present? ? flow_definition_param : flow.draft_definition
  end

  def persist_publish_definition!(flow, definition)
    flow.update!(
      draft_definition: definition,
      updated_by_id: Current.user&.id
    )
  end

  def serialized_flow(flow)
    {
      id: flow.id,
      name: flow.name,
      description: flow.description,
      status: flow.status,
      draft_definition: flow.draft_definition,
      published_version: serialized_version(flow.published_version),
      updated_at: flow.updated_at
    }
  end

  def serialized_version(version)
    return nil if version.blank?

    {
      id: version.id,
      version: version.version,
      checksum: version.checksum,
      published_at: version.published_at,
      definition: version.definition
    }
  end

  def check_authorization
    authorize(@agent_bot, policy_action)
  end

  def policy_action
    case action_name
    when 'show' then :show?
    when 'update' then :update?
    when 'validate' then :validate?
    when 'publish' then :publish?
    else "#{action_name}?".to_sym
    end
  end

  def native_chatbot_builder_enabled?
    Current.account.feature_enabled?('native_chatbot_builder') || native_chatbot_builder_globally_enabled?
  end

  def native_chatbot_builder_globally_enabled?
    Featurable::FEATURE_LIST.any? do |feature|
      feature['name'] == 'native_chatbot_builder' && feature['enabled'] == true
    end
  end
end
