class CreateNativeChatbotBuilderTables < ActiveRecord::Migration[7.0]
  def change
    create_table :chatbot_flows do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :agent_bot, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.jsonb :draft_definition, null: false, default: {}
      t.bigint :published_version_id
      t.bigint :created_by_id
      t.bigint :updated_by_id

      t.timestamps
    end

    create_table :chatbot_flow_versions do |t|
      t.references :chatbot_flow, null: false, foreign_key: true, index: true
      t.integer :version, null: false
      t.jsonb :definition, null: false, default: {}
      t.string :checksum
      t.datetime :published_at
      t.bigint :created_by_id

      t.timestamps
    end

    add_index :chatbot_flow_versions, [:chatbot_flow_id, :version], unique: true
    add_foreign_key :chatbot_flows, :chatbot_flow_versions, column: :published_version_id
    add_index :chatbot_flows, :published_version_id
    add_index :chatbot_flows, [:agent_bot_id], unique: true

    create_table :chatbot_sessions do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :conversation, null: false, foreign_key: true, index: true
      t.references :chatbot_flow_version, null: false, foreign_key: true, index: { name: 'index_sessions_on_flow_version' }
      t.integer :status, null: false, default: 0
      t.string :current_node_id
      t.jsonb :variables, null: false, default: {}
      t.jsonb :context, null: false, default: {}
      t.bigint :last_input_message_id
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    add_index :chatbot_sessions, :last_input_message_id
    add_index :chatbot_sessions, :status
    add_index :chatbot_sessions, [:conversation_id], unique: true, where: "status = 0", name: 'index_chatbot_sessions_on_active_conversation'

    create_table :chatbot_session_events do |t|
      t.references :chatbot_session, null: false, foreign_key: true, index: true
      t.integer :event_type, null: false
      t.string :node_id
      t.jsonb :payload, null: false, default: {}
      t.datetime :created_at, null: false
    end
  end
end
