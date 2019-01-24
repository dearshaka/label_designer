# frozen_string_literal: true

module LabelApp
  class LabelRepo < BaseRepo
    crud_calls_for :labels, name: :label, wrapper: Label
    crud_calls_for :multi_labels, name: :multi_label
    crud_calls_for :label_publish_logs, name: :label_publish_log, wrapper: LabelPublishLog
    crud_calls_for :label_publish_log_details, name: :label_publish_log_detail, wrapper: LabelPublishLogDetail

    def sub_label_list(sub_label_ids)
      DB[:labels].select(:id, :label_name)
                 .where(id: sub_label_ids)
                 .map { |r| [r[:label_name], r[:id]] }
    end

    def link_multi_label(id, sub_label_ids)
      DB.transaction do
        DB[:multi_labels].where(label_id: id).delete

        sub_label_ids.split(',').each_with_index do |sub_label_id, index|
          create_multi_label(label_id: id,
                             sub_label_id: sub_label_id,
                             print_sequence: index + 1)
        end
      end
    end

    def delete_label_with_sub_labels(id)
      DB.transaction do
        DB[:multi_labels].where(label_id: id).delete
        delete_label(id)
      end
    end

    def no_sub_labels(id)
      DB[:multi_labels].where(label_id: id).count
    end

    def sub_label_ids(id)
      DB[:multi_labels].where(label_id: id).order(:print_sequence).select_map(:sub_label_id)
    end

    # Re-build the sample data for a multi label from its sub-labels.
    def refresh_multi_label_variables(id)
      datalist = DB[:multi_labels].join(:labels, id: :sub_label_id)
                                  .where(label_id: id)
                                  .order(:print_sequence)
                                  .select(:sample_data)
                                  .map { |a| a[:sample_data] || {} }
      update_label(id, sample_data: hash_to_jsonb_str(new_sample(datalist)))
    end

    def label_publish_states(label_publish_log_id)
      query = <<~SQL
        SELECT l.label_name, d.server_ip, d.destination, d.status, d.errors, d.complete, d.failed
          FROM label_publish_log_details d
          JOIN labels l ON l.id = d.label_id
          WHERE d.label_publish_log_id = ?
          ORDER BY d.destination, l.label_name
      SQL
      DB[query, label_publish_log_id].all
    end

    def published_label_lookup(label_publish_log_id)
      query = <<~SQL
        SELECT DISTINCT l.id, l.label_name
        FROM label_publish_log_details p
        JOIN labels l ON l.id = p.label_id
        WHERE p.label_publish_log_id = ?
      SQL
      Hash[DB[query, label_publish_log_id].map { |r| [r[:label_name], r[:id]] }]
    end

    def published_label_conditions(label_publish_log_id)
      complete_query = <<~SQL
        SELECT COUNT(id)
          FROM public.label_publish_log_details
          WHERE label_publish_log_id = ?
            AND NOT complete
      SQL

      fail_query = <<~SQL
        SELECT COUNT(id)
          FROM public.label_publish_log_details
          WHERE label_publish_log_id = ?
            AND failed
      SQL

      complete = DB[complete_query, label_publish_log_id].get.zero?
      failed = DB[fail_query, label_publish_log_id].get.positive?
      [complete, failed]
    end

    private

    # Re-combine F-numbers:
    # { F1, F2, F3 }, { F1, F2 } => { F1, F2, F3, F4, F5 }
    def new_sample(datalist)
      new_vars = {}
      cnt = 0
      offsets = datalist.map { |a| cnt += a.length }
      offsets.unshift(0)

      datalist.each_with_index do |data, index|
        data.each do |key, val|
          no = key.delete('F').to_i + offsets[index]
          new_vars["F#{no}"] = val
        end
      end
      new_vars
    end
  end
end
