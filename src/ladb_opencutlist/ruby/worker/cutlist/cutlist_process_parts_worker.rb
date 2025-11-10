module Ladb::OpenCutList

  require_relative '../../helper/part_drawing_helper'
  require_relative '../../helper/sanitizer_helper'
  require_relative '../common/common_write_drawing2d_worker'

  class CutlistProcessPartsWorker
    include SanitizerHelper
    include PartDrawingHelper
    def initialize(cutlist,
      path: ,
      part_ids: ,
      processor: ,
      update: ,
      unit: Length::Millimeter
    )
      @cutlist = cutlist
      @path = path
      @part_ids = part_ids
      @processor = processor
      @unit = unit
      @update = update
    end

    def run
      return { :errors => [ 'default.error' ] } unless @cutlist
      return { :errors => [ 'tab.cutlist.error.obsolete_cutlist' ] } if @cutlist.obsolete?

      model = Sketchup.active_model
      return { :errors => [ 'tab.cutlist.error.no_model' ] } unless model

      # Retrieve part
      parts = @cutlist.get_real_parts(@part_ids)
      return { :errors => [ 'tab.cutlist.error.unknow_part' ] } if parts.empty?
      # Ask for output dir
      dir = UI.select_directory(title: PLUGIN.get_i18n_string('tab.cutlist.write.title'), directory: '')
      if dir
        folder_names = []
        processors_directory = File.join(PLUGIN_DIR, 'posts')
        if Ladb::OpenCutList.const_defined?(:CutlistProcessPartWorker)
          Ladb::OpenCutList.send(:remove_const, :CutlistProcessPartWorker)
        end
        load @path
        parts.each do |part|
          next if part.virtual
          group = part.group
          folder_name = group.material_display_name
          folder_name = PLUGIN.get_i18n_string('tab.cutlist.material_undefined') if folder_name.nil? || folder_name.empty?
          folder_name += " - #{group.std_dimension}" unless group.std_dimension.empty?
          folder_name = _sanitize_filename(folder_name)
          folder_path = File.join(dir, folder_name)
          json_obj = {
            'id' => part.id,
            'name' => _sanitize_filename(part.name),
            'number' => part.number,
            'folder_path' => folder_path,
            'material_name' => group.material_display_name,
            'material_std_dimension' => group.std_dimension,
            'faces' => {},
            'flipped' => part.flipped,
            'description' => part.description,
            'count' => part.count,
            'tags' => part.tags.dup,
            'content_layers' => part.content_layers.dup
          }
          begin
            unless folder_names.include?(folder_name)
              if File.exist?(folder_path) && !@update
                if UI.messagebox(PLUGIN.get_i18n_string('core.messagebox.dir_override', { :target => folder_name, :parent => File.basename(dir) }), MB_YESNO) == IDYES
                    FileUtils.remove_dir(folder_path, true)
                else
                    return { :cancelled => true }
                end
              end
              if !File.exist?(folder_path)
                Dir.mkdir(folder_path)
              end
              folder_names << folder_name
            end
            count = 0

            faces_type = ["PART_DRAWING_TYPE_2D_TOP" ,"PART_DRAWING_TYPE_2D_BOTTOM","PART_DRAWING_TYPE_2D_LEFT","PART_DRAWING_TYPE_2D_RIGHT", "PART_DRAWING_TYPE_2D_FRONT","PART_DRAWING_TYPE_2D_BACK"]

            # 6.times do |i|
            faces_type.each_with_index do |face_name, i|
              face_number = i + 1
              json_obj['faces'][face_name] = {}
              current_face_obj = json_obj['faces'][face_name]
              drawing_def = _compute_part_drawing_def(face_number, part,
                                                      ignore_edges: false,
                                                      origin_position: CommonDrawingDecompositionWorker::ORIGIN_POSITION_BOUNDS_MIN
              )

              return { :errors => [ 'tab.cutlist.error.unknow_part' ] } unless drawing_def.is_a?(DrawingDef)

              projection_def = CommonDrawingProjectionWorker.new(drawing_def,
                                                                origin_position: CommonDrawingProjectionWorker::ORIGIN_POSITION_BOUNDS_MIN,
                                                                merge_holes: true,
                                                                merge_holes_overflow: 0.to_l,
                                                                mask: nil,
              ).run
              if projection_def.is_a?(DrawingProjectionDef)
                bounds = projection_def.bounds
                unit_sign, unit_factor = _get_unit_sign_and_factor(@unit)
                unit_transformation = Geom::Transformation.scaling(unit_factor, unit_factor, 1.0)
                origin = Geom::Point3d.new(bounds.min.x, -(bounds.height + bounds.min.y)).transform(unit_transformation)
                size = Geom::Point3d.new(bounds.width, bounds.height).transform(unit_transformation)
                x = _get_value(origin.x)
                y = _get_value(origin.y)
                width = _get_value(size.x)
                height = _get_value(size.y)
                current_face_obj['origin'] = {
                  'x' => x,   
                  'y' => y
                }
                current_face_obj['unit_sign'] = unit_sign
                current_face_obj['size'] = {
                  'width' => width,   
                  'height' => height,
                  'thickness' => 0
                }
                unless projection_def.layer_defs.empty?
                  _write_projection_def(current_face_obj, projection_def,
                                            transformation: unit_transformation,
                                            unit_transformation: unit_transformation,
                                            unit_sign: unit_sign)
                end
                if(face_name == "PART_DRAWING_TYPE_2D_TOP")
                    json_obj['size'] = current_face_obj['size']
                    json_obj['origin'] = current_face_obj['origin']
                    json_obj['unit_sign'] = current_face_obj['unit_sign']
                    json_obj['size']['thickness'] = current_face_obj['size']['thickness']
                end
              end
            end
            # json_str = JSON.pretty_generate(json_obj)
            # puts json_str
            worker_module = CutlistProcessPartWorker.new(part: json_obj)
            worker_module.run
          rescue => e
            puts e.inspect
            puts e.backtrace
            return { :errors => [ [ 'core.error.failed_export_to', { :path => folder_path, :error => e.message } ] ] }
          end
        end
        { :export_path => dir }
      end
    end

    def _get_unit_sign_and_factor(unit)
      require_relative '../../utils/dimension_utils'
      case unit
      when DimensionUtils::INCHES
        unit_factor = 1.0
        unit_sign = 'in'
      when DimensionUtils::CENTIMETER
        unit_factor = 1.0.to_l.to_cm
        unit_sign = 'cm'
      else
        unit_factor = 1.0.to_l.to_mm
        unit_sign = 'mm'
      end
      return unit_sign, unit_factor
    end

    def _get_value(value)
      value.to_f.round(3)
    end

    def _write_projection_def( face_obj, projection_def,
                                  transformation: IDENTITY,
                                  unit_transformation: IDENTITY,
                                  unit_sign: '')

      require_relative '../../model/drawing/drawing_projection_def'

      return unless projection_def.is_a?(DrawingProjectionDef)

      require_relative '../../utils/transformation_utils'

      face_obj['works'] = []
      projection_def.layer_defs.sort_by { |v| [ v.type_outer? ? 0 : v.depth, v.type_paths? ? 1 : 0 ] }.each do |layer_def| 
        layer_depth = _get_value(Geom::Point3d.new(layer_def.depth, 0).transform(unit_transformation).x)
        if layer_def.type_outer? || layer_def.depth == 0
          face_obj['size']['thickness'] = layer_depth
          next
        end

        layer_def.poly_defs.each do |poly_def|
          if poly_def.curve_def
            if poly_def.curve_def.circle?
              # Simplify circle drawing by using only xradius
              portion = poly_def.curve_def.portions.first
              center = portion.ellipse_def.center
              radius = portion.ellipse_def.xradius
              position1 = Geom::Point3d.new(
                center.x - radius,
                center.y
              ).transform(transformation)
              position2 = Geom::Point3d.new(
                center.x + radius,
                center.y
              ).transform(transformation)
              radius = Geom::Point3d.new(radius, 0).transform(unit_transformation)
              x1 = _get_value(position1.x)
              y1 = _get_value(position1.y)
              x2 = _get_value(position2.x)
              y2 = _get_value(-position2.y)
              r = _get_value(radius.x)
              face_obj['works'] << {
                'type' => 'hole', 
                'x' => x1 + r,
                'y' => y1,
                'z' => -layer_depth,
                'd' => r * 2
              }
            else
              # Extract loop points from ordered edges and arc curves
              portion_setup = []
              # depth = Geom::Point3d.new(layer_def.depth, 0).transform(unit_transformation)
              poly_def.curve_def.portions.map.with_index { |portion, index|
                start_point = portion.start_point.transform(transformation)
                end_point = portion.end_point.transform(transformation)
                x = _get_value(start_point.x)
                y = _get_value(start_point.y)
                if(index == 0)
                  portion_setup << {
                    "type" => "L01",
                    "x" => x, 
                    "y" => y,
                    "z" => -layer_depth
                  }
                end
                if portion.is_a?(Geometrix::ArcCurvePortionDef)
                  radius = Geom::Point3d.new(portion.ellipse_def.xradius, portion.ellipse_def.yradius).transform(unit_transformation)
                  middle = portion.mid_point.transform(transformation)
                  rx = _get_value(radius.x)
                  ry = _get_value(radius.y)
                  xrot = -portion.ellipse_def.angle.radians.round(3)
                  lflag = 0
                  sflag = portion.ccw? ? 0 : 1
                  x1 = _get_value(middle.x)
                  y1 = _get_value(-middle.y)
                  x2 = _get_value(end_point.x)
                  y2 = _get_value(-end_point.y)
                  portion_setup << {
                    'type' => "A11", 
                    'rx' => rx,
                    'ry' => ry,
                    'z' => -layer_depth, 
                    'xrot' => xrot, 
                    'lflag' => lflag, 
                    'sflag' => sflag, 
                    'x1' => x1, 
                    'y1' => -y1, 
                    'x' => x2,
                    'y' => -y2
                  }
                else
                  x = _get_value(end_point.x)
                  y = _get_value(end_point.y)
                  portion_setup << {
                    "type" => "L01", 
                    "x" => x, 
                    "y" => y,
                    "z" => -layer_depth
                  }
                end
              }
              face_obj['works'] << {
                'type' => "path", 
                'datas' => portion_setup 
              }
            end
          end
        end
      end
    end
  end
end
