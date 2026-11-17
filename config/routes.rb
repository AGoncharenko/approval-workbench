Rails.application.routes.draw do
  resource :session, only: %i[ new create destroy ]
  resources :invoices do
    resources :transitions, only: :create
  end
  # No show or edit page: the role is the only editable field, changed inline from the list.
  namespace :admin do
    resources :users, only: %i[ index update ]
    resources :audit_events, only: :index
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # 200 only when the primary database answers, 503 otherwise; Render's deploy health check uses it.
  get "up" => "health#show", as: :health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "invoices#index"
end
