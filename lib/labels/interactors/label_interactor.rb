# frozen_string_literal: true

module LabelApp
  class LabelInteractor < BaseInteractor # rubocop:disable Metrics/ClassLength
    def repo
      @repo ||= LabelRepo.new
    end

    def label(id)
      repo.find_label(id)
    end

    def validate_label_params(params)
      LabelSchema.call(params)
    end

    def pre_create_label(params)
      res = validate_label_params(params)
      return validation_failed_response(res) unless res.messages.empty?
      attrs = {
        container_type: params[:container_type],
        commodity: params[:commodity],
        market: params[:market],
        language: params[:language],
        category: params[:category],
        variable_set: params[:variable_set],
        sub_category: params[:sub_category]
      }
      success_response('Ok', attrs)
    end

    def create_label(params) # rubocop:disable Metrics/AbcSize
      res = validate_label_params(params)
      return validation_failed_response(res) unless res.messages.empty?
      id = nil
      repo.transaction do
        id = repo.create_label(include_created_by_in_changeset(res))
        log_transaction
      end
      instance = label(id)
      success_response("Created label #{instance.label_name}",
                       instance)
    rescue Sequel::UniqueConstraintViolation
      validation_failed_response(OpenStruct.new(messages: { label_name: ['This label already exists'] }))
    end

    def update_label(id, params)
      res = validate_label_params(params)
      return validation_failed_response(res) unless res.messages.empty?
      repo.transaction do
        repo.update_label(id, include_updated_by_in_changeset(res))
        log_transaction
      end
      instance = label(id)
      success_response("Updated label #{instance.label_name}",
                       instance)
    end

    def delete_label(id)
      instance = label(id)
      repo.transaction do
        if instance.multi_label
          repo.delete_label_with_sub_labels(id)
        else
          repo.delete_label(id)
        end
        log_status('labels', id, 'DELETED')
        log_transaction
      end
      success_response("Deleted label #{instance.label_name}")
    end

    def archive_label(id)
      repo.transaction do
        repo.update_label(id, active: false)
        log_status('labels', id, 'ARCHIVED')
        log_transaction
      end
      instance = label(id)
      success_response("Archived label #{instance.label_name}", instance)
    end

    def un_archive_label(id)
      repo.transaction do
        repo.update_label(id, active: true)
        log_status('labels', id, 'UN-ARCHIVED')
        log_transaction
      end
      instance = label(id)
      success_response("Un-Archived label #{instance.label_name}", instance)
    end

    def link_multi_label(id, sub_label_ids)
      repo.transaction do
        repo.link_multi_label(id, sub_label_ids)
        log_status('labels', id, 'SUB_LABELS_LINKED')
      end
      success_response('Linked sub-labels for a multi-label')
    end

    def validate_clone_label_params(params)
      LabelCloneSchema.call(params)
    end

    def can_preview?(id)
      if label(id).multi_label && repo.no_sub_labels(id).zero?
        failed_response('This multi-label does not have any linked sub-labels')
      else
        success_response('ok')
      end
    end

    def can_email_preview?(id)
      res = can_preview?(id)
      return res unless res.success
      if @user.email.nil? || @user.email.strip.empty?
        failed_response('You do not have an email address set')
      elsif label(id).multi_label
        failed_response('A multi-label cannot be emailed. Please email each sub label on its own')
      else
        success_response('ok')
      end
    end

    def prepare_clone_label(id, params)
      res = validate_clone_label_params(params)
      return validation_failed_response(res) unless res.messages.empty?
      instance = label(id)
      attrs = {
        label_name: params[:label_name],
        container_type: instance.container_type,
        commodity: instance.commodity,
        market: instance.market,
        language: instance.language,
        category: instance.category,
        variable_set: instance.variable_set,
        sub_category: instance.sub_category,
        cloned_from_id: id
      }
      success_response('Ok', attrs)
    end

    def background_images(id)
      res = can_preview?(id)
      return res unless res.success
      ids = if label(id).multi_label
              repo.sub_label_ids(id)
            else
              [id]
            end
      success_response('ok', ids)
    end

    def png_image(id)
      instance = label(id)
      instance.png_image
    end

    def label_zip(id)
      instance = label(id)
      LabelFiles.new.make_label_zip(instance)
    end

    def label_export(id)
      instance = label(id)
      raise 'Multi-labels cannot be exported' if instance.multi_label
      LabelFiles.new.make_export_zip(instance)
    end

    def import_label(params) # rubocop:disable Metrics/AbcSize
      return failed_response('No file selected to import') unless params[:import_file] && (tempfile = params[:import_file][:tempfile])
      attrs = {
        label_name: params[:label_name],
        container_type: params[:container_type],
        commodity: params[:commodity],
        market: params[:market],
        language: params[:language],
        category: params[:category],
        variable_set: params[:variable_set],
        sub_category: params[:sub_category]
      }
      attrs = LabelFiles.new.import_file(tempfile, attrs)
      id = nil
      repo.transaction do
        id = repo.create_label(attrs)
        log_transaction
      end
      instance = label(id)
      success_response("Imported label #{instance.label_name}", instance)
    rescue Sequel::UniqueConstraintViolation
      validation_failed_response(OpenStruct.new(messages: { label_name: ['This label already exists'] }))
    end

    def do_preview(id, screen_or_print, vars) # rubocop:disable Metrics/AbcSize
      instance = label(id)
      # Store the input variables:
      # repo.update_label(id, sample_data: "{#{vars.map { |k, v| %("#{k}":"#{v}") }.join(',')}}")
      repo.update_label(id, sample_data: repo.hash_for_jsonb_col(vars))

      fname, binary_data = LabelFiles.new.make_label_zip(instance, vars)
      # File.open('zz.zip', 'w') { |f| f.puts binary_data }

      mes_repo = MesserverApp::MesserverRepo.new
      res = mes_repo.preview_label(screen_or_print, vars, fname, binary_data)
      if res.success
        success_response("Sent preview to #{screen_or_print}.", OpenStruct.new(fname: fname, body: res.instance))
      else
        failed_response(res.message)
      end
    end

    def batch_print(id, params)
      instance = label(id)
      quantity = params.delete(:no_of_labels)
      printer_code = params.delete(:printer)

      repo.update_label(id, sample_data: repo.hash_for_jsonb_col(params))

      mes_repo = MesserverApp::MesserverRepo.new
      mes_repo.print_label(instance.label_name, params, quantity, printer_code)
    end

    def email_preview(id, params) # rubocop:disable Metrics/AbcSize
      vars = params.dup
      vars.delete_if { |k| %i[to subject body cc].include?(k) }
      instance = label(id)
      repo.update_label(id, sample_data: repo.hash_for_jsonb_col(vars))

      fname, binary_data = LabelFiles.new.make_label_zip(instance, vars)
      # File.open('zz.zip', 'w') { |f| f.puts binary_data }

      mes_repo = MesserverApp::MesserverRepo.new
      res = mes_repo.preview_label('screen', vars, fname, binary_data)
      if res.success
        filepath = Tempfile.open([fname, '.png'], 'public/tempfiles') do |f|
          f.write(res.instance)
          f.path
        end
        File.chmod(0o644, filepath) # Ensure web app can read the image.

        mail_opts = {
          from: @user.email,
          to: params[:to],
          subject: params[:subject],
          body: params[:body],
          attachments: [{ path: filepath }]
        }
        mail_opts[:cc] = params[:cc] if params[:cc]
        DevelopmentApp::SendMailJob.enqueue(mail_opts)
        log_status('labels', id, 'EMAILED FOR APPROVAL', comment: "to #{params[:to]}")
        success_response('Email has been queued for sending. Please check your inbox for a copy.')
      else
        failed_response(res.message)
      end
    end

    def refresh_multi_label_variables(id)
      repo.transaction do
        repo.refresh_multi_label_variables(id)
        log_transaction
      end
      success_response('Preview values have been built up from the sub-labels')
    end

    def label_designer_page(opts = {}) # rubocop:disable Metrics/AbcSize
      variable_set = find_variable_set(opts)

      lbl_config = label_config(opts)
      raise Crossbeams::FrameworkError, "Label dimension \"#{lbl_config[:labelDimension]}\" is not defined. Please call support." unless AppConst::LABEL_SIZES[lbl_config[:labelDimension]]

      Crossbeams::LabelDesigner::Config.configure do |config|
        config.label_variable_types = label_variables(variable_set)
        config.label_config = lbl_config.to_json
        config.label_sizes = AppConst::LABEL_SIZES.to_json
        config.allow_compound_variable = variable_set != 'CMS'
      end

      page = Crossbeams::LabelDesigner::Page.new(opts[:id])
      # page.json_load_path = '/load_label_via_json' # Override config just before use.
      # page.json_save_path =  opts[:id].nil? ? '/save_label' : "/save_label/#{opts[:id]}"
      html = page.render      # --> ASCII-8BIT
      css  = page.css         # --> ASCII-8BIT
      js   = page.javascript  # --> UTF-8

      # ">>> HTML enc"
      # #<Encoding:ASCII-8BIT>
      # ">>> CSS enc"
      # #<Encoding:ASCII-8BIT>
      # ">>> JS enc"
      # #<Encoding:UTF-8>

      # TODO: include csrf headers in the page....

      <<-HTML # --> UTF-8
      #{html}
      <% content_for :late_style do %>
        #{css}
      <% end %>
      <% content_for :late_javascript do %>
        #{js}
      <% end %>
      HTML
    end

    PNG_REGEXP = %r{\Adata:([-\w]+/[-\w\+\.]+)?;base64,(.*)}m
    def image_from_param(param)
      data_uri_parts = param.match(PNG_REGEXP) || []
      # extension = MIME::Types[data_uri_parts[1]].first.preferred_extension
      # file_name = "testpng.#{extension}"
      Base64.decode64(data_uri_parts[2])
    end

    def complete_a_label(id, params)
      res = complete_a_record(:labels, id, params.merge(enqueue_job: false))
      # Use params to trigger alert...
      if res.success
        success_response(res.message, label(id))
      else
        failed_response(res.message, label(id))
      end
    end

    def reopen_a_label(id, params)
      res = reopen_a_record(:labels, id, params.merge(enqueue_job: false))
      # Use params to trigger alert...
      if res.success
        success_response(res.message, label(id))
      else
        failed_response(res.message, label(id))
      end
    end

    def approve_or_reject_a_label(id, params)
      res = if params[:approve_action] == 'a'
              approve_a_record(:labels, id, params.merge(enqueue_job: false))
            else
              reject_a_record(:labels, id, params.merge(enqueue_job: false))
            end
      # Use params to trigger alert...
      if res.success
        NotifyLabelApprovedJob.enqueue(id)
        success_response(res.message, label(id))
      else
        failed_response(res.message, label(id))
      end
    end

    def assert_permission!(task, id = nil)
      res = TaskPermissionCheck::Label.call(task, id)
      raise Crossbeams::TaskNotPermittedError, res.message unless res.success
    end

    private

    def find_variable_set(opts)
      key = opts[:variable_set]
      key = variable_set_from_label(opts[:id]) if key.nil?
      key || 'CMS'
    end

    def variable_set_from_label(id)
      return nil if id.nil?
      repo = LabelApp::LabelRepo.new
      repo.find_label(id).variable_set
    end

    def label_variables(variable_set)
      LabelApp::SharedConfigRepo.new.remote_object_variable_groups(variable_set)
    end

    def label_instance_for_config(opts)
      if opts[:id]
        repo = LabelApp::LabelRepo.new
        label = repo.find_label(opts[:id])
        if opts[:cloned]
          label = LabelApp::Label.new(label.to_h.merge(id: nil, label_name: opts[:label_name]))
        end
        label
      else
        OpenStruct.new(opts)
      end
    end

    def label_config(opts)
      label = label_instance_for_config(opts)

      config = {
        labelState: opts[:id].nil? ? 'new' : 'edit',
        labelName:  label.label_name,
        savePath: label.id.nil? ? '/save_label' : "/save_label/#{label.id}",
        labelDimension: label.label_dimension,
        id: label.id,
        pixelPerMM: label.px_per_mm,
        labelJSON: label.label_json
      }
      config
    end
  end
end
