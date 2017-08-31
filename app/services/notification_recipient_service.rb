#
# Used by NotificationService to determine who should receive notification
#
module NotificationRecipientService
  def self.notifiable_users(users, *args)
    users.compact.map { |u| NotificationRecipient.new(u, *args) }.select(&:notifiable?).map(&:user)
  end

  def self.notifiable?(user, *args)
    NotificationRecipient.new(user, *args).notifiable?
  end

  def self.build_recipients(*a)
    Builder::Default.new(*a).recipient_users
  end

  def self.build_new_note_recipients(*a)
    Builder::NewNote.new(*a).recipient_users
  end

  module Builder
    class Base
      def initialize(*)
        raise 'abstract'
      end

      def build!
        raise 'abstract'
      end

      def filter!
        recipients.select!(&:notifiable?)
      end

      def acting_user
        current_user
      end

      def target
        raise 'abstract'
      end

      # rubocop:disable Rails/Delegate
      def project
        target.project
      end

      def recipients
        @recipients ||= []
      end

      def <<(pair)
        users, type = pair

        if users.is_a?(ActiveRecord::Relation)
          users = users.includes(:notification_settings)
        end

        users = Array(users)
        users.compact!
        recipients.concat(users.map { |u| make_recipient(u, type) })
      end

      def user_scope
        User.includes(:notification_settings)
      end

      def make_recipient(user, type)
        NotificationRecipient.new(
          user, type,
          project: project,
          custom_action: custom_action,
          target: target,
          acting_user: acting_user
        )
      end

      def recipient_users
        @recipient_users ||=
          begin
            build!
            filter!
            users = recipients.map(&:user)
            users.uniq!
            users.freeze
          end
      end

      def custom_action
        nil
      end

      protected

      def add_participants(user)
        return unless target.respond_to?(:participants)

        self << [target.participants(user), :participating]
      end

      # Get project/group users with CUSTOM notification level
      def add_custom_notifications
        user_ids = []

        # Users with a notification setting on group or project
        user_ids += user_ids_notifiable_on(project, :custom)
        user_ids += user_ids_notifiable_on(project.group, :custom)

        # Users with global level custom
        user_ids_with_project_level_global = user_ids_notifiable_on(project, :global)
        user_ids_with_group_level_global   = user_ids_notifiable_on(project.group, :global)

        global_users_ids = user_ids_with_project_level_global.concat(user_ids_with_group_level_global)
        user_ids += user_ids_with_global_level_custom(global_users_ids, custom_action)

        self << [user_scope.where(id: user_ids), :watch]
      end

      def add_project_watchers
        self << [project_watchers, :watch]
      end

      # Get project users with WATCH notification level
      def project_watchers
        project_members_ids = user_ids_notifiable_on(project)

        user_ids_with_project_global = user_ids_notifiable_on(project, :global)
        user_ids_with_group_global   = user_ids_notifiable_on(project.group, :global)

        user_ids = user_ids_with_global_level_watch((user_ids_with_project_global + user_ids_with_group_global).uniq)

        user_ids_with_project_setting = select_project_members_ids(user_ids_with_project_global, user_ids)
        user_ids_with_group_setting = select_group_members_ids(project.group, project_members_ids, user_ids_with_group_global, user_ids)

        user_scope.where(id: user_ids_with_project_setting.concat(user_ids_with_group_setting).uniq)
      end

      def add_subscribed_users
        return unless target.respond_to? :subscribers

        self << [target.subscribers(project), :subscription]
      end

      def user_ids_notifiable_on(resource, notification_level = nil)
        return [] unless resource

        scope = resource.notification_settings

        if notification_level
          scope = scope.where(level: NotificationSetting.levels[notification_level])
        end

        scope.pluck(:user_id)
      end

      # Build a list of user_ids based on project notification settings
      def select_project_members_ids(global_setting, user_ids_global_level_watch)
        user_ids = user_ids_notifiable_on(project, :watch)

        # If project setting is global, add to watch list if global setting is watch
        user_ids + (global_setting & user_ids_global_level_watch)
      end

      # Build a list of user_ids based on group notification settings
      def select_group_members_ids(group, project_members, global_setting, user_ids_global_level_watch)
        uids = user_ids_notifiable_on(group, :watch)

        # Group setting is global, add to user_ids list if global setting is watch
        uids + (global_setting & user_ids_global_level_watch) - project_members
      end

      def user_ids_with_global_level_watch(ids)
        settings_with_global_level_of(:watch, ids).pluck(:user_id)
      end

      def user_ids_with_global_level_custom(ids, action)
        settings_with_global_level_of(:custom, ids).pluck(:user_id)
      end

      def settings_with_global_level_of(level, ids)
        NotificationSetting.where(
          user_id: ids,
          source_type: nil,
          level: NotificationSetting.levels[level]
        )
      end

      def add_labels_subscribers(labels: nil)
        return unless target.respond_to? :labels

        (labels || target.labels).each do |label|
          self << [label.subscribers(project), :subscription]
        end
      end
    end

    class Default < Base
      attr_reader :target
      attr_reader :current_user
      attr_reader :action
      attr_reader :previous_assignee
      attr_reader :skip_current_user
      def initialize(target, current_user, action:, previous_assignee: nil, skip_current_user: true)
        @target = target
        @current_user = current_user
        @action = action
        @previous_assignee = previous_assignee
        @skip_current_user = skip_current_user
      end

      def build!
        add_participants(current_user)
        add_project_watchers
        add_custom_notifications

        # Re-assign is considered as a mention of the new assignee
        case custom_action
        when :reassign_merge_request
          self << [previous_assignee, :mention]
          self << [target.assignee, :mention]
        when :reassign_issue
          previous_assignees = Array(previous_assignee)
          self << [previous_assignees, :mention]
          self << [target.assignees, :mention]
        end

        add_subscribed_users

        if [:new_issue, :new_merge_request].include?(custom_action)
          add_labels_subscribers
        end
      end

      def acting_user
        current_user if skip_current_user
      end

      # Build event key to search on custom notification level
      # Check NotificationSetting::EMAIL_EVENTS
      def custom_action
        @custom_action ||= "#{action}_#{target.class.model_name.name.underscore}".to_sym
      end
    end

    class NewNote < Base
      attr_reader :note
      def initialize(note)
        @note = note
      end

      def target
        note.noteable
      end

      # NOTE: may be nil, in the case of a PersonalSnippet
      #
      # (this is okay because NotificationRecipient is written
      # to handle nil projects)
      def project
        note.project
      end

      def build!
        # Add all users participating in the thread (author, assignee, comment authors)
        add_participants(note.author)
        self << [note.mentioned_users, :mention]

        unless note.for_personal_snippet?
          # Merge project watchers
          add_project_watchers

          # Merge project with custom notification
          add_custom_notifications
        end

        add_subscribed_users
      end

      def custom_action
        :new_note
      end

      def acting_user
        note.author
      end
    end
  end
end
