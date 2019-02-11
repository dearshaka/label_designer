# frozen_string_literal: true

module Labels
  module Labels
    module Label
      class BatchPrint
        def self.call(id, form_values: nil, form_errors: nil, remote: true)
          label, rules, xml_vars = rules_and_fields(id)

          layout = Crossbeams::Layout::Page.build(rules) do |page|
            page.form_object OpenStruct.new(label.sample_data || {})
            page.form_values form_values
            page.form_errors form_errors
            page.form do |form|
              form.action "/labels/labels/labels/#{id}/batch_print"
              form.remote! if remote
              form.method :update
              form.add_field :no_of_labels
              form.add_field :printer
              xml_vars.each do |v|
                form.add_field v.to_sym
              end
            end
          end

          layout
        end

        def self.rules_and_fields(id)
          this_repo = LabelApp::LabelRepo.new
          repo      = LabelApp::PrinterRepo.new
          obj       = this_repo.find_label(id)
          printers  = repo.printers_for(obj.px_per_mm)
          if obj.multi_label
            rules_for_multiple(this_repo, obj, printers)
          else
            rules_for_single(obj, printers)
          end
        end

        def self.rules_for_multiple(repo, obj, printers) # rubocop:disable Metrics/AbcSize
          count = 0
          xml_vars = []
          vartypes = []
          repo.sub_label_ids(obj.id).each do |sub_label_id|
            sub_label = repo.find_label(sub_label_id)
            doc       = Nokogiri::XML(sub_label.variable_xml)
            sub_xml_vars = doc.css('variable_field_count').map do |var|
              "F#{var.text.sub(/f/i, '').to_i + count}"
            end
            count += sub_xml_vars.length
            xml_vars += sub_xml_vars
            vartypes += doc.css('variable_type').map(&:text)
          end
          combos    = Hash[xml_vars.zip(vartypes)]

          rules     = { fields: {
            no_of_labels: { renderer: :integer, required: true },
            printer: { renderer: :select,
                       options: printers,
                       caption: 'Printer',
                       required: true }
          }, name: 'label' }
          xml_vars.each { |v| rules[:fields][v.to_sym] = { caption: "#{v} (#{combos[v]})" } }
          [obj, rules, xml_vars]
        end

        def self.rules_for_single(obj, printers)
          doc       = Nokogiri::XML(obj.variable_xml)
          xml_vars  = doc.css('variable_field_count').map(&:text)
          vartypes  = doc.css('variable_type').map(&:text)
          combos    = Hash[xml_vars.zip(vartypes)]

          rules     = { fields: {
            no_of_labels: { renderer: :integer, required: true },
            printer: { renderer: :select,
                       options: printers,
                       caption: 'Printer',
                       required: true }
          }, name: 'label' }
          xml_vars.each { |v| rules[:fields][v.to_sym] = { caption: "#{v} (#{combos[v]})" } }
          [obj, rules, xml_vars]
        end
      end
    end
  end
end
