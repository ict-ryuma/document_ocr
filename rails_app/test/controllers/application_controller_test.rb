# frozen_string_literal: true

require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "health endpoint returns success" do
    get "/health"
    assert_response :success
  end

  test "health endpoint returns JSON" do
    get "/health", as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert json.key?("status")
  end

  test "health endpoint includes service status in non-production" do
    get "/health", as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert json.key?("services") unless Rails.env.production?
  end
end
