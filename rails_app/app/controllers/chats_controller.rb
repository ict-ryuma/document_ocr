# frozen_string_literal: true

# Chats Controller
# Handles Meister Bot conversational AI chatbot interactions
class ChatsController < ApplicationController
  # GET /chat
  # Show chat interface
  def index
    # 現在のチャットスレッドを取得または新規作成
    @chat_thread = find_or_create_chat_thread
  end

  # POST /chat/message
  # Send a message to the chatbot and get a response
  def create
    user_message = params[:message]

    if user_message.blank?
      render json: { error: "Message cannot be blank" }, status: :bad_request
      return
    end

    # 現在のチャットスレッドを取得または新規作成
    chat_thread = find_or_create_chat_thread

    # Call OpenAI Chat Service (DBベース)
    chat_service = OpenaiChatService.new(chat_thread: chat_thread)
    result = chat_service.chat(user_message)

    # Respond with bot's message
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # Append user message bubble
          turbo_stream.append("chat-messages", partial: "chats/message", locals: {
            message: user_message,
            role: "user",
            timestamp: Time.current
          }),
          # Append bot response bubble
          turbo_stream.append("chat-messages", partial: "chats/message", locals: {
            message: result[:response],
            role: "assistant",
            timestamp: Time.current,
            function_called: result[:function_called],
            search_results: result[:search_results]
          }),
          # Clear input field
          turbo_stream.update("message-input", "")
        ]
      end

      format.json do
        render json: {
          response: result[:response],
          function_called: result[:function_called],
          search_results: result[:search_results],
          timestamp: Time.current
        }
      end
    end
  rescue => e
    Rails.logger.error "[ChatsController] Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("chat-messages", partial: "chats/message", locals: {
          message: "申し訳ありません。エラーが発生しました。もう一度お試しください。",
          role: "assistant",
          timestamp: Time.current,
          error: true
        })
      end

      format.json do
        render json: { error: e.message }, status: :internal_server_error
      end
    end
  end

  # DELETE /chat/reset
  # Clear conversation history
  def reset
    # 現在のチャットスレッドを削除して新しいスレッドを作成
    if session[:chat_thread_id].present?
      ChatThread.find_by(id: session[:chat_thread_id])&.destroy
    end
    session.delete(:chat_thread_id)

    # 新しいチャットスレッドを作成
    chat_thread = find_or_create_chat_thread

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.update("chat-messages", ""),
          turbo_stream.append("chat-messages", partial: "chats/message", locals: {
            message: "会話履歴をリセットしました。何でも聞いてね！",
            role: "assistant",
            timestamp: Time.current
          })
        ]
      end

      format.json do
        render json: { success: true, message: "Conversation reset" }
      end
    end
  end

  private

  # 現在のチャットスレッドを取得または新規作成
  def find_or_create_chat_thread
    # セッションにthread_idがあれば取得
    if session[:chat_thread_id].present?
      thread = ChatThread.find_by(id: session[:chat_thread_id])
      return thread if thread
    end

    # なければ新規作成
    thread = ChatThread.create!
    session[:chat_thread_id] = thread.id
    thread
  end
end
