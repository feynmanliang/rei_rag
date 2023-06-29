defmodule ReiRagWeb.ChatLive.Index do
  use ReiRagWeb, :live_view
  import Phoenix.Component

  @impl true
  def mount(_params, _session, socket) do
    form = %{
      "message" => "I want to buy a snowboard for my son.",
      "response" => ""
    }

    {:ok,
     socket
     |> assign(:form, to_form(form))
     |> assign(:messages, [
       %{
         role: "system",
         content: "You are a REI salesperson. Help a user find the right product for them."
       }
     ])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="row">
        <div class="col-12">
          <h1 class="text-4xl">REI Product Chat</h1>
        </div>
      </div>
      <.simple_form for={@form} phx-submit="send">
        <div :for={message <- @messages}>
          <%= message.role %>:
          <%= message.content %>
        </div>
        <.input field={@form[:message]} type="text" placeholder="Type your message here..." />
        <.button type="submit" phx-disable-with="Sending...">
          Send
        </.button>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def handle_event("send", form, socket) do
    messages =
      if length(socket.assigns[:messages]) == 1 do
        query =
          chat_completion([
            %{
              role: "user",
              content: """
              Given the following user message, determine a product to search for. Output just the product name.

              <message>
              #{form["message"]}
              </message>
              """
            }
          ])
          |> Phoenix.HTML.html_escape()
          |> elem(1)

        product_urls =
          Req.get!("https://www.rei.com/search?q=#{query}").body
          |> Floki.parse_document!()
          |> Floki.find("a")
          |> Floki.attribute("href")
          |> Enum.filter(&String.contains?(&1, "/product/"))

        context =
          Enum.take(product_urls, 3)
          |> Enum.map(fn url ->
            html =
              Req.get!("https://www.rei.com#{url}").body
              |> Floki.parse_document!()

            %{
              name: Floki.find(html, "#product-page-title") |> Floki.text(),
              price: Floki.find(html, "#buy-box-product-price") |> Floki.text(),
              description: Floki.find(html, ".product-features") |> Floki.text()
            }
          end)
          |> Jason.encode!()

        socket.assigns[:messages] ++
          [
            %{
              role: "system",
              content: """
              Here are some products that match your search:

              <context>
              #{context}
              </context>
              """
            }
          ]
      else
        socket.assigns[:messages]
      end

    messages =
      messages ++
        [
          %{role: "user", content: form["message"]}
        ]

    ai_response = chat_completion(messages)

    messages =
      (messages ++
         [
           %{role: "assistant", content: ai_response}
         ])

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(
       form:
         %{
           "message" => form["message"],
           "response" => ai_response
         }
         |> to_form()
     )}
  end

  defp chat_completion(messages) do
    Req.post!("https://api.openai.com/v1/chat/completions",
      headers: [Authorization: ~s'Bearer #{System.get_env("OPENAI_API_KEY")}'],
      json: %{
        model: "gpt-3.5-turbo",
        messages: messages
      }
    ).body["choices"]
    |> List.first()
    |> get_in(["message", "content"])
  end
end
