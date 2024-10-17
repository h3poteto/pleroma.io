# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ApiSpec.InstanceOperation do
  alias OpenApiSpex.Operation
  alias OpenApiSpex.Schema

  def open_api_operation(action) do
    operation = String.to_existing_atom("#{action}_operation")
    apply(__MODULE__, operation, [])
  end

  def show_operation do
    %Operation{
      tags: ["Instance misc"],
      summary: "Retrieve instance information",
      description: "Information about the server",
      operationId: "InstanceController.show",
      responses: %{
        200 => Operation.response("Instance", "application/json", instance())
      }
    }
  end

  def show2_operation do
    %Operation{
      tags: ["Instance misc"],
      summary: "Retrieve instance information",
      description: "Information about the server",
      operationId: "InstanceController.show2",
      responses: %{
        200 => Operation.response("Instance", "application/json", instance2())
      }
    }
  end

  def peers_operation do
    %Operation{
      tags: ["Instance misc"],
      summary: "Retrieve list of known instances",
      operationId: "InstanceController.peers",
      responses: %{
        200 => Operation.response("Array of domains", "application/json", array_of_domains())
      }
    }
  end

  def rules_operation do
    %Operation{
      tags: ["Instance misc"],
      summary: "Retrieve list of instance rules",
      operationId: "InstanceController.rules",
      responses: %{
        200 => Operation.response("Array of domains", "application/json", array_of_rules())
      }
    }
  end

  defp instance do
    %Schema{
      type: :object,
      properties: %{
        accounts: %Schema{
          type: :object,
          properties: %{
            max_featured_tags: %Schema{
              type: :integer,
              description: "The maximum number of featured tags allowed for each account."
            }
          }
        },
        uri: %Schema{type: :string, description: "The domain name of the instance"},
        title: %Schema{type: :string, description: "The title of the website"},
        description: %Schema{
          type: :string,
          description: "Admin-defined description of the Pleroma site"
        },
        version: %Schema{
          type: :string,
          description: "The version of Pleroma installed on the instance"
        },
        email: %Schema{
          type: :string,
          description: "An email that may be contacted for any inquiries",
          format: :email
        },
        urls: %Schema{
          type: :object,
          description: "URLs of interest for clients apps",
          properties: %{
            streaming_api: %Schema{
              type: :string,
              description: "Websockets address for push streaming"
            }
          }
        },
        stats: %Schema{
          type: :object,
          description: "Statistics about how much information the instance contains",
          properties: %{
            user_count: %Schema{
              type: :integer,
              description: "Users registered on this instance"
            },
            status_count: %Schema{
              type: :integer,
              description: "Statuses authored by users on instance"
            },
            domain_count: %Schema{
              type: :integer,
              description: "Domains federated with this instance"
            }
          }
        },
        thumbnail: %Schema{
          type: :string,
          description: "Banner image for the website",
          nullable: true
        },
        languages: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Primary languages of the website and its staff"
        },
        registrations: %Schema{type: :boolean, description: "Whether registrations are enabled"},
        # Extra (not present in Mastodon):
        max_toot_chars: %Schema{
          type: :integer,
          description: ": Posts character limit (CW/Subject included in the counter)"
        },
        poll_limits: %Schema{
          type: :object,
          description: "A map with poll limits for local polls",
          properties: %{
            max_options: %Schema{
              type: :integer,
              description: "Maximum number of options."
            },
            max_option_chars: %Schema{
              type: :integer,
              description: "Maximum number of characters per option."
            },
            min_expiration: %Schema{
              type: :integer,
              description: "Minimum expiration time (in seconds)."
            },
            max_expiration: %Schema{
              type: :integer,
              description: "Maximum expiration time (in seconds)."
            }
          }
        },
        upload_limit: %Schema{
          type: :integer,
          description: "File size limit of uploads (except for avatar, background, banner)"
        },
        avatar_upload_limit: %Schema{type: :integer, description: "The title of the website"},
        background_upload_limit: %Schema{type: :integer, description: "The title of the website"},
        banner_upload_limit: %Schema{type: :integer, description: "The title of the website"},
        background_image: %Schema{
          type: :string,
          format: :uri,
          description: "The background image for the website"
        }
      },
      example: %{
        "avatar_upload_limit" => 2_000_000,
        "background_upload_limit" => 4_000_000,
        "background_image" => "/static/image.png",
        "banner_upload_limit" => 4_000_000,
        "description" => "Pleroma: An efficient and flexible fediverse server",
        "email" => "lain@lain.com",
        "languages" => ["en"],
        "max_toot_chars" => 5000,
        "poll_limits" => %{
          "max_expiration" => 31_536_000,
          "max_option_chars" => 200,
          "max_options" => 20,
          "min_expiration" => 0
        },
        "registrations" => false,
        "stats" => %{
          "domain_count" => 2996,
          "status_count" => 15_802,
          "user_count" => 5
        },
        "thumbnail" => "https://lain.com/instance/thumbnail.jpeg",
        "title" => "lain.com",
        "upload_limit" => 16_000_000,
        "uri" => "https://lain.com",
        "urls" => %{
          "streaming_api" => "wss://lain.com"
        },
        "version" => "2.7.2 (compatible; Pleroma 2.0.50-536-g25eec6d7-develop)",
        "rules" => array_of_rules()
      }
    }
  end

  defp instance2 do
    %Schema{
      type: :object,
      properties: %{
        domain: %Schema{type: :string, description: "The domain name of the instance"},
        title: %Schema{type: :string, description: "The title of the website"},
        version: %Schema{
          type: :string,
          description: "The version of Pleroma installed on the instance"
        },
        source_url: %Schema{
          type: :string,
          description: "The version of Pleroma installed on the instance"
        },
        description: %Schema{
          type: :string,
          description: "Admin-defined description of the Pleroma site"
        },
        usage: %Schema{
          type: :object,
          description: "Instance usage statistics",
          properties: %{
            users: %Schema{
              type: :object,
              description: "User count statistics",
              properties: %{
                active_month: %Schema{
                  type: :integer,
                  description: "Monthly active users"
                }
              }
            }
          }
        },
        email: %Schema{
          type: :string,
          description: "An email that may be contacted for any inquiries",
          format: :email
        },
        urls: %Schema{
          type: :object,
          description: "URLs of interest for clients apps",
          properties: %{}
        },
        stats: %Schema{
          type: :object,
          description: "Statistics about how much information the instance contains",
          properties: %{
            user_count: %Schema{
              type: :integer,
              description: "Users registered on this instance"
            },
            status_count: %Schema{
              type: :integer,
              description: "Statuses authored by users on instance"
            },
            domain_count: %Schema{
              type: :integer,
              description: "Domains federated with this instance"
            }
          }
        },
        thumbnail: %Schema{
          type: :object,
          properties: %{
            url: %Schema{
              type: :string,
              description: "Banner image for the website",
              nullable: true
            }
          }
        },
        languages: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Primary languages of the website and its staff"
        },
        registrations: %Schema{
          type: :object,
          description: "Registrations-related configuration",
          properties: %{
            enabled: %Schema{
              type: :boolean,
              description: "Whether registrations are enabled"
            },
            approval_required: %Schema{
              type: :boolean,
              description: "Whether users need to be manually approved by admin"
            }
          }
        },
        configuration: %Schema{
          type: :object,
          description: "Instance configuration",
          properties: %{
            accounts: %Schema{
              type: :object,
              properties: %{
                max_featured_tags: %Schema{
                  type: :integer,
                  description: "The maximum number of featured tags allowed for each account."
                },
                max_pinned_statuses: %Schema{
                  type: :integer,
                  description: "The maximum number of pinned statuses for each account."
                }
              }
            },
            urls: %Schema{
              type: :object,
              properties: %{
                streaming: %Schema{
                  type: :string,
                  description: "Websockets address for push streaming"
                }
              }
            },
            statuses: %Schema{
              type: :object,
              description: "A map with poll limits for local statuses",
              properties: %{
                characters_reserved_per_url: %Schema{
                  type: :integer,
                  description:
                    "Each URL in a status will be assumed to be exactly this many characters."
                },
                max_characters: %Schema{
                  type: :integer,
                  description: "Posts character limit (CW/Subject included in the counter)"
                },
                max_media_attachments: %Schema{
                  type: :integer,
                  description: "Media attachment limit"
                }
              }
            },
            media_attachments: %Schema{
              type: :object,
              description: "A map with poll limits for media attachments",
              properties: %{
                image_size_limit: %Schema{
                  type: :integer,
                  description: "File size limit of uploaded images"
                },
                video_size_limit: %Schema{
                  type: :integer,
                  description: "File size limit of uploaded videos"
                }
              }
            },
            polls: %Schema{
              type: :object,
              description: "A map with poll limits for local polls",
              properties: %{
                max_options: %Schema{
                  type: :integer,
                  description: "Maximum number of options."
                },
                max_characters_per_option: %Schema{
                  type: :integer,
                  description: "Maximum number of characters per option."
                },
                min_expiration: %Schema{
                  type: :integer,
                  description: "Minimum expiration time (in seconds)."
                },
                max_expiration: %Schema{
                  type: :integer,
                  description: "Maximum expiration time (in seconds)."
                }
              }
            }
          }
        }
      }
    }
  end

  defp array_of_domains do
    %Schema{
      type: :array,
      items: %Schema{type: :string},
      example: ["pleroma.site", "lain.com", "bikeshed.party"]
    }
  end

  defp array_of_rules do
    %Schema{
      type: :array,
      items: %Schema{
        type: :object,
        properties: %{
          id: %Schema{type: :string},
          text: %Schema{type: :string},
          hint: %Schema{type: :string}
        }
      }
    }
  end
end
