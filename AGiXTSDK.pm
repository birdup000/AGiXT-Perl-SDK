use strict;
use warnings;

use JSON;
use LWP::UserAgent;
use HTTP::Request::Common;
use Data::Dumper;
use MIME::Base64;
use Time::HiRes qw(time);
use Digest::SHA qw(sha256_hex);
use File::Slurp;
use UUID::Tiny;
use Audio::Wav;

# Replace with your preferred audio library if needed
# Install using: cpanm Audio::Wav

# Pydantic and Enum are not directly applicable in Perl
# You'll need to handle data validation and enum-like behavior manually

package ChatCompletions {
    use Moo;

    has model => (
        is => 'ro',
        default => 'gpt4free',
    );
    has messages => (
        is => 'ro',
        default => sub { [] },
    );
    has temperature => (
        is => 'ro',
        default => 0.9,
    );
    has top_p => (
        is => 'ro',
        default => 1.0,
    );
    # ... (other attributes similar to Python)

    sub BUILDARGS {
        my ($class, %args) = @_;
        return { %args };
    }
};

sub get_tokens {
    my ($text) = @_;
    # Replace with your preferred tokenizer
    # Example using Lingua::EN::Sentence:
    # Install using: cpanm Lingua::EN::Sentence
    
    my @tokens = split /\s+/, $text;
    return scalar @tokens;
}

sub parse_response {
    my ($response) = @_;
    print "Status Code: " . $response->code . "\n";
    print "Response JSON:\n";
    if ($response->is_success) {
        print to_json(from_json($response->decoded_content), { pretty => 1 });
    } else {
        print $response->decoded_content . "\n";
        die "Request failed\n";
    }
    print "\n";
}

package AGiXTSDK {
    use Moo;

    has base_uri => (
        is => 'ro',
        default => 'http://localhost:7437',
    );
    has verbose => (
        is => 'ro',
        default => 0,
    );
    has headers => (
        is => 'rw',
        default => sub { { 'Content-Type' => 'application/json' } },
    );
    has failures => (
        is => 'rw',
        default => 0,
    );

    sub BUILDARGS {
        my ($class, %args) = @_;
        $args{base_uri} =~ s/\/$// if $args{base_uri}; 
        if ($args{api_key}) {
            $args{api_key} =~ s/^(Bearer|bearer)\s+//;
            $args{headers} = {
                'Authorization' => $args{api_key},
                'Content-Type' => 'application/json',
            };
        }
        return { %args };
    }

    sub handle_error {
        my ($self, $error) = @_;
        print "Error: $error\n";
        die "Unable to retrieve data. $error";
    }

    sub login {
        my ($self, $email, $otp) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/v1/login",
            Content_Type => 'application/json',
            Content => to_json({ email => $email, token => $otp }),
        ));
        parse_response($response) if $self->{verbose};
        my $json = from_json($response->decoded_content);
        if (exists $json->{detail}) {
            my $detail = $json->{detail};
            if ($detail =~ /\?token=(.+)/) {
                my $token = $1;
                $self->{headers} = { 'Authorization' => $token };
                print "Log in at $detail\n";
                return $token;
            }
        }
        return $json;
    }

    # ... (other methods will follow a similar pattern)

    sub register_user {
        my ($self, $email, $first_name, $last_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/v1/user",
            Content_Type => 'application/json',
            Content => to_json({
                email => $email,
                first_name => $first_name,
                last_name => $last_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        my $json = from_json($response->decoded_content);

        # Assuming you have a Perl equivalent of pyotp
        # Install using: cpanm Google::Authenticator
        if (exists $json->{otp_uri}) {
            my $mfa_token = $json->{otp_uri};
            $mfa_token =~ s/.*secret=([^&]+).*/$1/;
            # Replace with Google::Authenticator logic
            # my $totp = Google::Authenticator->new(secret => $mfa_token);
            # my $otp = $totp->code;
            # $self->login(email => $email, otp => $otp);
            return $json->{otp_uri};
        } else {
            return $json;
        }
    }

    sub user_exists {
        my ($self, $email) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/v1/user/exists?email=$email"));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }


    sub update_user {
        my ($self, %kwargs) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PUT(
            "$self->{base_uri}/v1/user",
            %$self->{headers},
            Content => to_json(\%kwargs),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub get_user {
        my ($self) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/v1/user", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub get_providers {
        my ($self) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/provider", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{providers}};
    }

    sub get_providers_by_service {
        my ($self, $service) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/providers/service/$service", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{providers}};
    }

    sub get_provider_settings {
        my ($self, $provider_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/provider/$provider_name", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{settings}};
    }

    sub get_embed_providers {
        my ($self) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/embedding_providers", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{providers}};
    }

    sub get_embedders {
        my ($self) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/embedders", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{embedders}};
    }

    sub add_agent {
        my ($self, $agent_name, $settings, $commands, $training_urls) = @_;
        $settings //= {};
        $commands //= {};
        $training_urls //= [];
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent",
            %$self->{headers},
            Content => to_json({
                agent_name => $agent_name,
                settings => $settings,
                commands => $commands,
                training_urls => $training_urls,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub import_agent {
        my ($self, $agent_name, $settings, $commands) = @_;
        $settings //= {};
        $commands //= {};
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/import",
            %$self->{headers},
            Content => to_json({
                agent_name => $agent_name,
                settings => $settings,
                commands => $commands,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }


    sub rename_agent {
        my ($self, $agent_name, $new_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PATCH(
            "$self->{base_uri}/api/agent/$agent_name",
            %$self->{headers},
            Content => to_json({ new_name => $new_name }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub update_agent_settings {
        my ($self, $agent_name, $settings) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PUT(
            "$self->{base_uri}/api/agent/$agent_name",
            %$self->{headers},
            Content => to_json({
                settings => $settings,
                agent_name => $agent_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub update_agent_commands {
        my ($self, $agent_name, $commands) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PUT(
            "$self->{base_uri}/api/agent/$agent_name/commands",
            %$self->{headers},
            Content => to_json({
                commands => $commands,
                agent_name => $agent_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub delete_agent {
        my ($self, $agent_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE("$self->{base_uri}/api/agent/$agent_name", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub get_agents {
        my ($self) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/agent", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{agents}};
    }

    sub get_agentconfig {
        my ($self, $agent_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/agent/$agent_name", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{agent}};
    }

    sub get_conversations {
        my ($self, $agent_name) = @_;
        $agent_name //= ""; # Optional agent_name
        my $url = "$self->{base_uri}/api/conversations";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET($url, %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{conversations}};
    }

    sub get_conversations_with_ids {
        my ($self) = @_;
        my $url = "$self->{base_uri}/api/conversations";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET($url, %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{conversations_with_ids}};
    }

    sub get_conversation {
        my ($self, $agent_name, $conversation_name, $limit, $page) = @_;
        $limit //= 100;
        $page //= 1;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET(
            "$self->{base_uri}/api/conversation",
            %$self->{headers},
            Content => to_json({
                conversation_name => $conversation_name,
                agent_name => $agent_name,
                limit => $limit,
                page => $page,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{conversation_history}};
    }

    sub new_conversation {
        my ($self, $agent_name, $conversation_name, $conversation_content) = @_;
        $conversation_content //= [];
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/conversation",
            %$self->{headers},
            Content => to_json({
                conversation_name => $conversation_name,
                agent_name => $agent_name,
                conversation_content => $conversation_content,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{conversation_history}};
    }

    sub rename_conversation {
        my ($self, $agent_name, $conversation_name, $new_name) = @_;
        $new_name //= "-";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PUT(
            "$self->{base_uri}/api/conversation",
            %$self->{headers},
            Content => to_json({
                conversation_name => $conversation_name,
                new_conversation_name => $new_name,
                agent_name => $agent_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{conversation_name};
    }

    sub delete_conversation {
        my ($self, $agent_name, $conversation_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE(
            "$self->{base_uri}/api/conversation",
            %$self->{headers},
            Content => to_json({
                conversation_name => $conversation_name,
                agent_name => $agent_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub delete_conversation_message {
        my ($self, $agent_name, $conversation_name, $message) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE(
            "$self->{base_uri}/api/conversation/message",
            %$self->{headers},
            Content => to_json({
                message => $message,
                agent_name => $agent_name,
                conversation_name => $conversation_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }


    sub update_conversation_message {
        my ($self, $agent_name, $conversation_name, $message, $new_message) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PUT(
            "$self->{base_uri}/api/conversation/message",
            %$self->{headers},
            Content => to_json({
                message => $message,
                new_message => $new_message,
                agent_name => $agent_name,
                conversation_name => $conversation_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub new_conversation_message {
        my ($self, $role, $message, $conversation_name) = @_;
        $role //= "user";
        $message //= "";
        $conversation_name //= ""; 
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/conversation/message",
            %$self->{headers},
            Content => to_json({
                role => $role,
                message => $message,
                conversation_name => $conversation_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub prompt_agent {
        my ($self, $agent_name, $prompt_name, $prompt_args) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/prompt",
            %$self->{headers},
            Content => to_json({
                prompt_name => $prompt_name,
                prompt_args => $prompt_args,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{response};
    }

    sub instruct {
        my ($self, $agent_name, $user_input, $conversation) = @_;
        return $self->prompt_agent(
            agent_name => $agent_name,
            prompt_name => 'instruct',
            prompt_args => {
                user_input => $user_input,
                disable_memory => 1, # Assuming boolean is represented as 1/0
                conversation_name => $conversation,
            },
        );
    }

    sub chat {
        my ($self, $agent_name, $user_input, $conversation, $context_results) = @_;
        $context_results //= 4;
        return $self->prompt_agent(
            agent_name => $agent_name,
            prompt_name => 'Chat',
            prompt_args => {
                user_input => $user_input,
                context_results => $context_results,
                conversation_name => $conversation,
                disable_memory => 1, # Assuming boolean is represented as 1/0
            },
        );
    }

    sub smartinstruct {
        my ($self, $agent_name, $user_input, $conversation) = @_;
        return $self->run_chain(
            chain_name => 'Smart Instruct',
            user_input => $user_input,
            agent_name => $agent_name,
            all_responses => 0, # Assuming boolean is represented as 1/0
            from_step => 1,
            chain_args => {
                conversation_name => $conversation,
                disable_memory => 1, # Assuming boolean is represented as 1/0
            },
        );
    }

    sub smartchat {
        my ($self, $agent_name, $user_input, $conversation) = @_;
        return $self->run_chain(
            chain_name => 'Smart Chat',
            user_input => $user_input,
            agent_name => $agent_name,
            all_responses => 0, # Assuming boolean is represented as 1/0
            from_step => 1,
            chain_args => {
                conversation_name => $conversation,
                disable_memory => 1, # Assuming boolean is represented as 1/0
            },
        );
    }

    sub get_commands {
        my ($self, $agent_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/agent/$agent_name/command", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{commands}};
    }

    sub toggle_command {
        my ($self, $agent_name, $command_name, $enable) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PATCH(
            "$self->{base_uri}/api/agent/$agent_name/command",
            %$self->{headers},
            Content => to_json({
                command_name => $command_name,
                enable => $enable,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub execute_command {
        my ($self, $agent_name, $command_name, $command_args, $conversation_name) = @_;
        $conversation_name //= "AGiXT Terminal Command Execution";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/command",
            %$self->{headers},
            Content => to_json({
                command_name => $command_name,
                command_args => $command_args,
                conversation_name => $conversation_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{response};
    }

    sub get_chains {
        my ($self) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/chain", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub get_chain {
        my ($self, $chain_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/chain/$chain_name", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{chain}};
    }

    sub get_chain_responses {
        my ($self, $chain_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/chain/$chain_name/responses", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{chain}};
    }

    sub get_chain_args {
        my ($self, $chain_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/chain/$chain_name/args", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{chain_args}};
    }

    sub run_chain {
        my ($self, $chain_name, $user_input, $agent_name, $all_responses, $from_step, $chain_args) = @_;
        $agent_name //= "";
        $all_responses //= 0;  # Assuming boolean is represented as 1/0
        $from_step //= 1;
        $chain_args //= {};
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/chain/$chain_name/run",
            %$self->{headers},
            Content => to_json({
                prompt => $user_input,
                agent_override => $agent_name,
                all_responses => $all_responses,
                from_step => int($from_step),
                chain_args => $chain_args,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub run_chain_step {
        my ($self, $chain_name, $step_number, $user_input, $agent_name, $chain_args) = @_;
        $agent_name //= "";
        $chain_args //= {};
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/chain/$chain_name/run/step/$step_number",
            %$self->{headers},
            Content => to_json({
                prompt => $user_input,
                agent_override => $agent_name,
                chain_args => $chain_args,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub add_chain {
        my ($self, $chain_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/chain",
            %$self->{headers},
            Content => to_json({ chain_name => $chain_name }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub import_chain {
        my ($self, $chain_name, $steps) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/chain/import",
            %$self->{headers},
            Content => to_json({
                chain_name => $chain_name,
                steps => $steps,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub rename_chain {
        my ($self, $chain_name, $new_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PUT(
            "$self->{base_uri}/api/chain/$chain_name",
            %$self->{headers},
            Content => to_json({ new_name => $new_name }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub delete_chain {
        my ($self, $chain_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE("$self->{base_uri}/api/chain/$chain_name", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub add_step {
        my ($self, $chain_name, $step_number, $agent_name, $prompt_type, $prompt) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/chain/$chain_name/step",
            %$self->{headers},
            Content => to_json({
                step_number => $step_number,
                agent_name => $agent_name,
                prompt_type => $prompt_type,
                prompt => $prompt,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub update_step {
        my ($self, $chain_name, $step_number, $agent_name, $prompt_type, $prompt) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PUT(
            "$self->{base_uri}/api/chain/$chain_name/step/$step_number",
            %$self->{headers},
            Content => to_json({
                step_number => $step_number,
                agent_name => $agent_name,
                prompt_type => $prompt_type,
                prompt => $prompt,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }


    sub move_step {
        my ($self, $chain_name, $old_step_number, $new_step_number) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PATCH(
            "$self->{base_uri}/api/chain/$chain_name/step/move",
            %$self->{headers},
            Content => to_json({
                old_step_number => $old_step_number,
                new_step_number => $new_step_number,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub delete_step {
        my ($self, $chain_name, $step_number) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE("$self->{base_uri}/api/chain/$chain_name/step/$step_number", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub add_prompt {
        my ($self, $prompt_name, $prompt, $prompt_category) = @_;
        $prompt_category //= "Default";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/prompt/$prompt_category",
            %$self->{headers},
            Content => to_json({
                prompt_name => $prompt_name,
                prompt => $prompt,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub get_prompt {
        my ($self, $prompt_name, $prompt_category) = @_;
        $prompt_category //= "Default";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/prompt/$prompt_category/$prompt_name", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{prompt}};
    }

    sub get_prompts {
        my ($self, $prompt_category) = @_;
        $prompt_category //= "Default";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/prompt/$prompt_category", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{prompts}};
    }


    sub get_prompt_categories {
        my ($self) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/prompt/categories", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{prompt_categories}};
    }

    sub get_prompt_args {
        my ($self, $prompt_name, $prompt_category) = @_;
        $prompt_category //= "Default";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/prompt/$prompt_category/$prompt_name/args", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{prompt_args}};
    }

    sub delete_prompt {
        my ($self, $prompt_name, $prompt_category) = @_;
        $prompt_category //= "Default";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE("$self->{base_uri}/api/prompt/$prompt_category/$prompt_name", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub update_prompt {
        my ($self, $prompt_name, $prompt, $prompt_category) = @_;
        $prompt_category //= "Default";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PUT(
            "$self->{base_uri}/api/prompt/$prompt_category/$prompt_name",
            %$self->{headers},
            Content => to_json({
                prompt => $prompt,
                prompt_name => $prompt_name,
                prompt_category => $prompt_category,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub rename_prompt {
        my ($self, $prompt_name, $new_name, $prompt_category) = @_;
        $prompt_category //= "Default";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PATCH(
            "$self->{base_uri}/api/prompt/$prompt_category/$prompt_name",
            %$self->{headers},
            Content => to_json({ prompt_name => $new_name }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub get_extension_settings {
        my ($self) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/extensions/settings", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{extension_settings}};
    }

    sub get_extensions {
        my ($self) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/extensions", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{extensions}};
    }

    sub get_command_args {
        my ($self, $command_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/extensions/$command_name/args", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{command_args}};
    }

    sub get_embedders_details {
        my ($self) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/embedders", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return %{from_json($response->decoded_content)->{embedders}};
    }

    sub positive_feedback {
        my ($self, $agent_name, $message, $user_input, $feedback, $conversation_name) = @_;
        $conversation_name //= "";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/feedback",
            %$self->{headers},
            Content => to_json({
                user_input => $user_input,
                message => $message,
                feedback => $feedback,
                positive => 1, # Assuming boolean is represented as 1/0
                conversation_name => $conversation_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub negative_feedback {
        my ($self, $agent_name, $message, $user_input, $feedback, $conversation_name) = @_;
        $conversation_name //= "";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/feedback",
            %$self->{headers},
            Content => to_json({
                user_input => $user_input,
                message => $message,
                feedback => $feedback,
                positive => 0, # Assuming boolean is represented as 1/0
                conversation_name => $conversation_name,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub learn_text {
        my ($self, $agent_name, $user_input, $text, $collection_number) = @_;
        $collection_number //= "0";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/learn/text",
            %$self->{headers},
            Content => to_json({
                user_input => $user_input,
                text => $text,
                collection_number => $collection_number,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub learn_url {
        my ($self, $agent_name, $url, $collection_number) = @_;
        $collection_number //= "0";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/learn/url",
            %$self->{headers},
            Content => to_json({
                url => $url,
                collection_number => $collection_number,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub learn_file {
        my ($self, $agent_name, $file_name, $file_content, $collection_number) = @_;
        $collection_number //= "0";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/learn/file",
            %$self->{headers},
            Content => to_json({
                file_name => $file_name,
                file_content => $file_content,
                collection_number => $collection_number,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub learn_github_repo {
        my ($self, $agent_name, $github_repo, $github_user, $github_token, $github_branch, $use_agent_settings, $collection_number) = @_;
        $github_user //= undef;  # Explicitly allow undef for optional parameters
        $github_token //= undef;
        $github_branch //= "main";
        $use_agent_settings //= 0; # Assuming boolean is represented as 1/0
        $collection_number //= "0";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/learn/github",
            %$self->{headers},
            Content => to_json({
                github_repo => $github_repo,
                github_user => $github_user,
                github_token => $github_token,
                github_branch => $github_branch,
                collection_number => $collection_number,
                use_agent_settings => $use_agent_settings,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub learn_arxiv {
        my ($self, $agent_name, $query, $arxiv_ids, $max_results, $collection_number) = @_;
        $query //= undef;
        $arxiv_ids //= undef;
        $max_results //= 5;
        $collection_number //= "0";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/learn/arxiv",
            %$self->{headers},
            Content => to_json({
                query => $query,
                arxiv_ids => $arxiv_ids,
                max_results => $max_results,
                collection_number => $collection_number,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub agent_reader {
        my ($self, $agent_name, $reader_name, $data, $collection_number) = @_;
        $collection_number //= "0";
        $data->{collection_number} = $collection_number unless exists $data->{collection_number};
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/reader/$reader_name",
            %$self->{headers},
            Content => to_json($data),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub wipe_agent_memories {
        my ($self, $agent_name, $collection_number) = @_;
        $collection_number //= "0";
        my $url = $collection_number == 0
            ? "$self->{base_uri}/api/agent/$agent_name/memory"
            : "$self->{base_uri}/api/agent/$agent_name/memory/$collection_number";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE($url, %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub delete_agent_memory {
        my ($self, $agent_name, $memory_id, $collection_number) = @_;
        $collection_number //= "0";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE("$self->{base_uri}/api/agent/$agent_name/memory/$collection_number/$memory_id", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub get_agent_memories {
        my ($self, $agent_name, $user_input, $limit, $min_relevance_score, $collection_number) = @_;
        $limit //= 5;
        $min_relevance_score //= 0.0;
        $collection_number //= "0";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/memory/$collection_number/query",
            %$self->{headers},
            Content => to_json({
                user_input => $user_input,
                limit => $limit,
                min_relevance_score => $min_relevance_score,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{memories}};
    }

    sub export_agent_memories {
        my ($self, $agent_name) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/agent/$agent_name/memory/export", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{memories}};
    }

    sub import_agent_memories {
        my ($self, $agent_name, $memories) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/memory/import",
            %$self->{headers},
            Content => to_json({ memories => $memories }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }


    sub create_dataset {
        my ($self, $agent_name, $dataset_name, $batch_size) = @_;
        $batch_size //= 4;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/memory/dataset",
            %$self->{headers},
            Content => to_json({
                dataset_name => $dataset_name,
                batch_size => $batch_size,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }


    sub get_browsed_links {
        my ($self, $agent_name, $collection_number) = @_;
        $collection_number //= "0";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/agent/$agent_name/browsed_links/$collection_number", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{links}};
    }


    sub delete_browsed_link {
        my ($self, $agent_name, $link, $collection_number) = @_;
        $collection_number //= "0";
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE(
            "$self->{base_uri}/api/agent/$agent_name/browsed_links",
            %$self->{headers},
            Content => to_json({
                link => $link,
                collection_number => $collection_number,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub get_memories_external_sources {
        my ($self, $agent_name, $collection_number) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET("$self->{base_uri}/api/agent/$agent_name/memory/external_sources/$collection_number", %$self->{headers}));
        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{external_sources}};
    }

    sub delete_memory_external_source {
        my ($self, $agent_name, $source, $collection_number) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE(
            "$self->{base_uri}/api/agent/$agent_name/memory/external_source",
            %$self->{headers},
            Content => to_json({
                external_source => $source,
                collection_number => $collection_number,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub train {
        my ($self, $agent_name, $dataset_name, $model, $max_seq_length, $huggingface_output_path, $private_repo) = @_;
        $agent_name //= "AGiXT";
        $dataset_name //= "dataset";
        $model //= "unsloth/mistral-7b-v0.2";
        $max_seq_length //= 16384;
        $huggingface_output_path //= "JoshXT/finetuned-mistral-7b-v0.2";
        $private_repo //= 1; # Assuming boolean is represented as 1/0
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/memory/dataset/$dataset_name/finetune",
            %$self->{headers},
            Content => to_json({
                model => $model,
                max_seq_length => $max_seq_length,
                huggingface_output_path => $huggingface_output_path,
                private_repo => $private_repo,
            }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{message};
    }

    sub text_to_speech {
        my ($self, $agent_name, $text) = @_;
        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/text_to_speech",
            %$self->{headers},
            Content => to_json({ text => $text }),
        ));
        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{url};
    }

    # This is a simplified version without async support
    sub chat_completions {
        my ($self, $prompt, $func) = @_;
        my $agent_name = $prompt->model;
        my $conversation_name = $prompt->user // "-"; 
        my $agent_config = $self->get_agentconfig(agent_name => $agent_name);
        my $agent_settings = exists $agent_config->{settings} ? $agent_config->{settings} : {};
        my @images;
        my $tts = 0;

        if (exists $agent_settings->{tts_provider}) {
            my $tts_provider = lc $agent_settings->{tts_provider};
            $tts = 1 if $tts_provider ne "none" && $tts_provider ne "";
        }

        my $new_prompt = "";
        for my $message (@{$prompt->messages}) {
            next unless exists $message->{content};

            if (ref $message->{content} eq 'ARRAY') {
                for my $msg (@{$message->{content}}) {
                    if (exists $msg->{text}) {
                        my $role = $message->{role} // "User";
                        $new_prompt .= "$msg->{text}\n\n" if lc $role eq "user";
                    }

                    # ... (Handle other message types: image_url, audio_url, video_url, file_url etc.)
                }
            } elsif (ref $message->{content} eq '') {
                my $role = $message->{role} // "User";
                if (lc $role eq "system") {
                    $new_prompt .= "$message->{content}\n\n" if $message->{content} =~ m{/}; 
                } elsif (lc $role eq "user") {
                    $new_prompt .= "$message->{content}\n\n";
                }
            }
        }

        $self->new_conversation_message(
            role => 'user',
            message => $new_prompt,
            conversation_name => $conversation_name,
        );

        my $response = $func->($new_prompt); 

        $self->new_conversation_message(
            role => $agent_name,
            message => $response,
            conversation_name => $conversation_name,
        );

        if ($tts) {
            $self->new_conversation_message(
                role => $agent_name,
                message => "[ACTIVITY] Generating audio response.",
                conversation_name => $conversation_name,
            );
            my $tts_response = $self->text_to_speech(agent_name => $agent_name, text => $response);
            $self->new_conversation_message(
                role => $agent_name,
                message => "<audio controls><source src=\"$tts_response\" type=\"audio/wav\"></audio>",
                conversation_name => $conversation_name,
            );
        }

        my $prompt_tokens = get_tokens($new_prompt);
        my $completion_tokens = get_tokens($response);
        my $total_tokens = $prompt_tokens + $completion_tokens;

        my $res_model = {
            id => $conversation_name,
            object => "chat.completion",
            created => int(time),
            model => $agent_name,
            choices => [
                {
                    index => 0,
                    message => {
                        role => "assistant",
                        content => $response,
                    },
                    finish_reason => "stop",
                    logprobs => undef,
                }
            ],
            usage => {
                prompt_tokens => $prompt_tokens,
                completion_tokens => $completion_tokens,
                total_tokens => $total_tokens,
            },
        };

        return $res_model;
    }

    # ... (Rest of the methods follow a similar pattern) 

    sub plan_task {
        my ($self, $agent_name, $user_input, $websearch, $websearch_depth, $conversation_name, $log_user_input, $log_output, $enable_new_command) = @_;
        $websearch //= 0; # Assuming boolean is represented as 1/0
        $websearch_depth //= 3;
        $conversation_name //= "";
        $log_user_input //= 1; # Assuming boolean is represented as 1/0
        $log_output //= 1; # Assuming boolean is represented as 1/0
        $enable_new_command //= 1; # Assuming boolean is represented as 1/0

        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/plan/task",
            %$self->{headers},
            Content => to_json({
                user_input => $user_input,
                websearch => $websearch,
                websearch_depth => $websearch_depth,
                conversation_name => $conversation_name,
                log_user_input => $log_user_input,
                log_output => $log_output,
                enable_new_command => $enable_new_command,
            }),
        ));

        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content)->{response};
    }


    sub convert_to_model {
        my ($self, $input_string, $model, $agent_name, $max_failures, $response_type) = @_;
        $input_string = "$input_string";
        $agent_name //= "gpt4free";
        $max_failures //= 3;
        $response_type //= undef;

        # Get field descriptions from the model class
        # (Assuming you have a way to get field annotations in Perl)
        my @field_descriptions;
        # Example using Moo attributes:
        # for my $attr ( $model->meta->get_attribute_list ) {
        #     my $description = "$attr->{name}: " . ref($attr->{type}) || $attr->{type};
        #     push @field_descriptions, $description; 
        # }

        my $schema = join "\n", @field_descriptions;

        my $response = $self->prompt_agent(
            agent_name => $agent_name,
            prompt_name => "Convert to Pydantic Model", 
            prompt_args => {
                schema => $schema,
                user_input => $input_string,
            },
        );

        if ($response =~ /```json(.*?)```/s) {
            $response = $1;
        } elsif ($response =~ /```(.*?)```/s) {
            $response = $1;
        }

        $response =~ s/^\s+|\s+$//g; # Trim whitespace

        eval {
            my $json = from_json($response);
            if ($response_type eq "json") {
                return $json;
            } else {
                # Create a new model object from the JSON data
                # (Assuming you have a way to do this in Perl)
                # Example using Moo:
                # return $model->new(%$json);
            }
        };

        if ($@) {
            $self->{failures}++;
            if ($self->{failures} > $max_failures) {
                warn "Error: $@. Failed to convert the response to the model after 3 attempts. Response: $response";
                return $response // "Failed to convert the response to the model.";
            } else {
                warn "Error: $@. Failed to convert the response to the model, trying again. $self->{failures}/3 failures. Response: $response";
                return $self->convert_to_model(
                    input_string => $input_string,
                    model => $model,
                    agent_name => $agent_name,
                    max_failures => $max_failures,
                    failures => $self->{failures},
                );
            }
        }
    }


    sub convert_list_of_dicts {
        my ($self, $data, $model, $agent_name) = @_;
        $agent_name //= "gpt4free";

        my $converted_data = $self->convert_to_model(
            input_string => to_json($data->[0], { pretty => 1 }),
            model => $model,
            agent_name => $agent_name,
        );

        my @mapped_list;
        for my $info (@$data) {
            my %new_data;
            for my $key (keys %$converted_data) {
                my @items = grep { $info->{$_} eq $converted_data->{$key} } keys %{$data->[0]};
                $new_data{$key} = $info->{$items[0]} if @items;
            }
            push @mapped_list, \%new_data;
        }

        return \@mapped_list;
    }


    sub get_dpo_response {
        my ($self, $agent_name, $user_input, $injected_memories, $conversation_name) = @_;
        $injected_memories //= 10;
        $conversation_name //= "";

        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/api/agent/$agent_name/dpo",
            %$self->{headers},
            Content => to_json({
                user_input => $user_input,
                injected_memories => $injected_memories,
                conversation_name => $conversation_name,
            }),
        ));

        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub transcribe_audio {
        my ($self, $file, $model, $language, $prompt, $response_format, $temperature) = @_;
        $language //= undef;
        $prompt //= undef;
        $response_format //= "json";
        $temperature //= 0.0;

        my $ua = LWP::UserAgent->new;

        # Read the audio file content
        my $audio_content = read_file($file, { binmode => ':raw' });

        my $response = $ua->request(POST(
            "$self->{base_uri}/v1/audio/transcriptions",
            %$self->{headers},
            Content_Type => 'form-data',
            Content => [
                file => [$file, $audio_content, Content_Type => 'audio/wav'],
                model => $model,
                language => $language,
                prompt => $prompt,
                response_format => $response_format,
                temperature => $temperature,
            ],
        ));

        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }


    sub translate_audio {
        my ($self, $file, $model, $prompt, $response_format, $temperature) = @_;
        $prompt //= undef;
        $response_format //= "json";
        $temperature //= 0.0;

        my $ua = LWP::UserAgent->new;

        # Read the audio file content
        my $audio_content = read_file($file, { binmode => ':raw' });

        my $response = $ua->request(POST(
            "$self->{base_uri}/v1/audio/translations",
            %$self->{headers},
            Content_Type => 'form-data',
            Content => [
                file => [$file, $audio_content, Content_Type => 'audio/wav'],
                model => $model,
                prompt => $prompt,
                response_format => $response_format,
                temperature => $temperature,
            ],
        ));

        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }


    sub generate_image {
        my ($self, $prompt, $model, $n, $size, $response_format) = @_;
        $model //= "dall-e-3";
        $n //= 1;
        $size //= "1024x1024";
        $response_format //= "url";

        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/v1/images/generations",
            %$self->{headers},
            Content => to_json({
                model => $model,
                prompt => $prompt,
                n => $n,
                size => $size,
                response_format => $response_format,
            }),
        ));

        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub oauth2_login {
        my ($self, $provider, $code, $referrer) = @_;
        $referrer //= undef;

        my %data = (code => $code);
        $data{referrer} = $referrer if defined $referrer;

        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(POST(
            "$self->{base_uri}/v1/oauth2/$provider",
            %$self->{headers},
            Content => to_json(\%data),
        ));

        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub update_conversation_message_by_id {
        my ($self, $message_id, $new_message, $conversation_name) = @_;

        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(PUT(
            "$self->{base_uri}/api/conversation/message/$message_id",
            %$self->{headers},
            Content => to_json({
                new_message => $new_message,
                conversation_name => $conversation_name,
            }),
        ));

        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub delete_conversation_message_by_id {
        my ($self, $message_id, $conversation_name) = @_;

        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(DELETE(
            "$self->{base_uri}/api/conversation/message/$message_id",
            %$self->{headers},
            Content => to_json({ conversation_name => $conversation_name }),
        ));

        parse_response($response) if $self->{verbose};
        return from_json($response->decoded_content);
    }

    sub get_unique_external_sources {
        my ($self, $agent_name, $collection_number) = @_;
        $collection_number //= "0";

        my $ua = LWP::UserAgent->new;
        my $response = $ua->request(GET(
            "$self->{base_uri}/api/agent/$agent_name/memory/external_sources/$collection_number",
            %$self->{headers},
        ));

        parse_response($response) if $self->{verbose};
        return @{from_json($response->decoded_content)->{external_sources}};
    }
};

1;