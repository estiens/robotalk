# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_07_29_005548) do
  create_table "conversation_participants", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.string "model_id", null: false
    t.text "system_prompt"
    t.integer "turn_order", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "character_prompt"
    t.string "name"
    t.index ["conversation_id", "model_id"], name: "idx_on_conversation_id_model_id_d24e5d49bf"
    t.index ["conversation_id", "turn_order"], name: "idx_on_conversation_id_turn_order_02738ed977", unique: true
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.integer "max_rounds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "conversation_topic"
    t.text "dialogue_instructions"
    t.string "model_id"
    t.integer "user_id", null: false
    t.string "status"
    t.integer "current_round", default: 1, null: false
    t.index ["created_at"], name: "index_conversations_on_created_at"
    t.index ["status"], name: "index_conversations_on_status"
    t.index ["user_id", "created_at"], name: "index_conversations_on_user_id_and_created_at"
    t.index ["user_id", "status"], name: "index_conversations_on_user_id_and_status"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.string "role"
    t.text "content"
    t.string "model_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "conversation_participant_id"
    t.integer "round_number"
    t.integer "round_id", null: false
    t.index ["conversation_participant_id"], name: "index_messages_on_conversation_participant_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["role"], name: "index_messages_on_conversation_id_and_role"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["round_id"], name: "index_messages_on_round_id"
    t.index ["round_number"], name: "index_messages_on_conversation_and_round"
  end

  create_table "rounds", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.integer "number", null: false
    t.string "status", default: "pending", null: false
    t.integer "next_participant_index", default: 0, null: false
    t.text "pause_reason"
    t.text "failure_reason"
    t.datetime "last_activity_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.index ["conversation_id", "number"], name: "index_rounds_on_conversation_id_and_number", unique: true
    t.index ["conversation_id"], name: "index_rounds_on_conversation_id"
    t.index ["last_activity_at"], name: "index_rounds_on_last_activity_at"
    t.index ["status"], name: "index_rounds_on_status"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.string "default_model"
    t.text "default_custom_system_prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "conversation_participants", "conversations"
  add_foreign_key "conversations", "users"
  add_foreign_key "messages", "conversation_participants"
  add_foreign_key "messages", "rounds"
  add_foreign_key "rounds", "conversations"
end
