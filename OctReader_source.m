classdef OctReader_source < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                        matlab.ui.Figure
        ZCroppingSlider                 matlab.ui.control.RangeSlider
        ZCroppingSliderLabel            matlab.ui.control.Label
        CrossSectionWindowSlider        matlab.ui.control.RangeSlider
        CrossSectionWindowSliderLabel   matlab.ui.control.Label
        ProjectionWindowSlider          matlab.ui.control.RangeSlider
        ProjectionWindowSliderLabel     matlab.ui.control.Label
        LocationSpinner                 matlab.ui.control.Spinner
        LocationSpinnerLabel            matlab.ui.control.Label
        CrossSectionDirectionButtonGroup  matlab.ui.container.ButtonGroup
        YButton                         matlab.ui.control.RadioButton
        XButton                         matlab.ui.control.RadioButton
        ViewersPanel                    matlab.ui.container.Panel
        UIAxesProjection                matlab.ui.control.UIAxes
        UIAxesCrossSection              matlab.ui.control.UIAxes
        OutputTextArea                  matlab.ui.control.TextArea
        OutputTextAreaLabel             matlab.ui.control.Label
        ProjectionTypeButtonGroup       matlab.ui.container.ButtonGroup
        MIPButton                       matlab.ui.control.RadioButton
        SVPButton                       matlab.ui.control.RadioButton
        LoadButton                      matlab.ui.control.Button
        ProjectionDirectionButtonGroup  matlab.ui.container.ButtonGroup
        AxialButton                     matlab.ui.control.RadioButton
        SaggitalButton                  matlab.ui.control.RadioButton
        EnFaceCoronalButton             matlab.ui.control.RadioButton
        LocationSlider                  matlab.ui.control.Slider
    end

    
    properties (Access = private)
        Data % 3d volume data
        ProjectionData % Projection Data
        CrossSectionData % Cross Section Data
        %CrossSectionX % Cross Section X Location
        %CrossSectionY % Cross Section Y Location
        PosLine % Line object that contains position line
        CrossSectionUpdateMutex
        CrossSectionIm
        ProjectionIm
        DicomInfo
    end
    
    methods (Access = private)
       
    end

    methods (Static)

        function data = readNPY(filename)
            % Function to read NPY files into matlab.
            % *** Only reads a subset of all possible NPY files, specifically N-D arrays of certain data types.
            % See https://github.com/kwikteam/npy-matlab/blob/master/tests/npy.ipynb for
            % more.
            %
            
            [shape, dataType, fortranOrder, littleEndian, totalHeaderLength, ~] = readNPYheader(filename);
            
            if littleEndian
                fid = fopen(filename, 'r', 'l');
            else
                fid = fopen(filename, 'r', 'b');
            end
            
            try
            
                [~] = fread(fid, totalHeaderLength, 'uint8');
            
                % read the data
                data = fread(fid, prod(shape), [dataType '=>' dataType]);
            
                if length(shape)>1 && ~fortranOrder
                    data = reshape(data, shape(end:-1:1));
                    data = permute(data, [length(shape):-1:1]);
                elseif length(shape)>1
                    data = reshape(data, shape);
                end
            
                fclose(fid);
            
            catch me
                fclose(fid);
                rethrow(me);
            end
        end

    end
    
    methods (Access = public)

        function results = load_init(app)
            proj_axis_but = app.ProjectionDirectionButtonGroup.SelectedObject;
            proj_axis_name = proj_axis_but.Text;
            switch proj_axis_name
                case "En-Face/Coronal"
                    proj_axis = 3;
                    tpose = false;
                case "Saggital"
                    proj_axis = 2;
                case "Axial"
                    proj_axis = 1;
                otherwise
                    throw(MException('OctReader:InvalidAxisType', "Invalid projection axis, add axis behavior to switch/case in update_projection()"))
            end
            app.ZCroppingSlider.Limits = [1, size(app.Data, proj_axis)];
            app.ZCroppingSlider.Value = [1, size(app.Data, proj_axis)];
            app.ZCroppingSlider.Step = 1;
        end
        
        function results = update_projection(app)
            if isempty(app.Data)
                return
            end
            proj_sel_but = app.ProjectionTypeButtonGroup.SelectedObject;
            proj_type = proj_sel_but.Text;
            proj_axis_but = app.ProjectionDirectionButtonGroup.SelectedObject;
            proj_axis_name = proj_axis_but.Text;
            proj_axis = -1;
            tpose = true;
            xRange = 1:size(app.Data, 1);
            yRange = 1:size(app.Data, 2);
            zRange = 1:size(app.Data, 3);
            r = int32(round(app.ZCroppingSlider.Value));
            
            switch proj_axis_name
                case "En-Face/Coronal"
                    proj_axis = 3;
                    tpose = false;
                    zRange = r(1):r(2);
                case "Saggital"
                    proj_axis = 2;
                    yRange = r(1):r(2);
                case "Axial"
                    proj_axis = 1;
                    xRange = r(1):r(2);
                otherwise
                    throw(MException('OctReader:InvalidAxisType', "Invalid projection axis, add axis behavior to switch/case in update_projection()"))
            end
            proj_status_text = sprintf("Computing: %s along axis: %d", proj_type, proj_axis);
            app.OutputTextArea.Value = proj_status_text;
            drawnow()
            
            %Add ability to set slices to exclude here
            switch proj_type
                case "SVP"
                    app.ProjectionData = mean(app.Data(xRange, yRange, zRange),proj_axis);
                case "MIP"
                    app.ProjectionData = max(app.Data(xRange, yRange, zRange),[],proj_axis);
                otherwise
                    throw(MException('OctReader:InvalidProjectionType', "Invalid projection type, add projection type behavior to switch/case in update_projection()"))
            end
      
            app.OutputTextArea.Value = strcat(proj_status_text, " Done!");
            drawnow()
            
            if tpose
                app.ProjectionData = squeeze(app.ProjectionData)';
            else
                app.ProjectionData = squeeze(app.ProjectionData);
            end
            
            %f = app.UIAxesProjection.ButtonDownFcn;
            set(app.UIAxesProjection, 'PickableParts', 'all', 'HitTest', 'on')
            app.ProjectionIm = imshow(app.ProjectionData, [], 'Parent', app.UIAxesProjection, 'Border', 'tight', 'InitialMagnification', 'fit', 'Interpolation', 'bilinear');
            colorbar(app.UIAxesProjection,"eastoutside")
            set(app.ProjectionIm,'HitTest','off')
            %app.UIAxesProjection.ButtonDownFcn = f;

            section_direction = app.CrossSectionDirectionButtonGroup.SelectedObject;
            section_axis = section_direction.Text;
            
            switch section_axis
                case "X"
                    app.LocationSpinner.Limits = [1 size(app.ProjectionData, 2)];
                    app.LocationSlider.Limits  = [1 size(app.ProjectionData, 2)];
                    app.ProjectionWindowSlider.Limits    = [0 max(app.Data,[],"all")];
                    app.CrossSectionWindowSlider.Limits    = [0 max(app.Data,[],"all")];
                case "Y"
                    app.LocationSpinner.Limits = [1 size(app.ProjectionData, 1)];
                    app.LocationSlider.Limits  = [1 size(app.ProjectionData, 1)];
                    app.ProjectionWindowSlider.Limits    = [0 max(app.Data,[],"all")];
                    app.CrossSectionWindowSlider.Limits    = [0 max(app.Data,[],"all")];
                    
                otherwise
                    throw(MException('OctReader:InvalidAxisType', "Invalid cross section direction, add to switch/case in update_cross_section()"))
            end
            app.ProjectionWindowSlider.Value = app.UIAxesProjection.CLim;
            app.LocationSlider.MajorTicksMode = 'auto';
        end



        function results = update_cross_section(app, X, Y)
            if isempty(app.Data)
                return
            end
            section_direction = app.CrossSectionDirectionButtonGroup.SelectedObject;
            section_axis = section_direction.Text;
            proj_axis_but = app.ProjectionDirectionButtonGroup.SelectedObject;
            proj_axis_name = proj_axis_but.Text;
            tpose = true;
            switch proj_axis_name
                case "En-Face/Coronal"
                    proj_axis = 3;
                case "Saggital"
                    proj_axis = 2;
                case "Axial"
                    proj_axis = 1;
                otherwise
                    throw(MException('OctReader:InvalidAxisType', "Invalid projection axis, add axis behavior to switch/case in update_cross_section()"))
            end
            
            switch section_axis
                case "X"
                    switch proj_axis
                        case 3
                            app.CrossSectionData = app.Data(Y, :, :);
                        case 2
                            app.CrossSectionData = app.Data(:, :, Y);% Need to test
                        case 1
                            app.CrossSectionData = app.Data(:, :, Y);% Need to test
                        otherwise
                            throw(MException('OctReader:InvalidAxisType', "Need to fill"))
                    end
                case "Y"
                    switch proj_axis
                        case 3
                            app.CrossSectionData = app.Data(:, X, :);
                        case 2
                            app.CrossSectionData = app.Data(X, :, :);% Need to test
                        case 1
                            app.CrossSectionData = app.Data(:, X, :);% Need to test
                        otherwise
                            throw(MException('OctReader:InvalidAxisType', "Need to fill"))
                    end
                otherwise
                    throw(MException('OctReader:InvalidAxisType', "Invalid cross section direction, add to switch/case in update_cross_section()"))
            end
            
            if tpose
                app.CrossSectionData = squeeze(app.CrossSectionData)';
            else
                app.CrossSectionData = squeeze(app.CrossSectionData);
            end
            

            %f = app.UIAxesProjection.ButtonDownFcn;
            set(app.UIAxesCrossSection, 'PickableParts', 'all', 'HitTest', 'on')
            app.CrossSectionIm = imshow(app.CrossSectionData, [], 'Parent', app.UIAxesCrossSection, 'Border', 'tight', 'InitialMagnification', 'fit', 'Interpolation', 'bilinear');
            colorbar(app.UIAxesCrossSection,"eastoutside")
            
            delete(app.PosLine)
            if strcmp(section_axis, "X")
                %l = line([],'Parent',app.UIAxesCrossSection);
                app.PosLine = line([0, size(app.ProjectionData, 2)], [Y, Y], 'Parent',app.UIAxesProjection, 'Color', 'r');
                app.LocationSpinner.Value = double(Y);
                app.LocationSlider.Value = double(Y);
            else
                %l = line([(app.CrossSectionX, 0) (app.CrossSectionX, size(app.CrossSectionData, 2))],'Parent',app.UIAxesCrossSection);
                app.PosLine = line([X, X], [0, size(app.ProjectionData, 1)],'Parent',app.UIAxesProjection, 'Color', 'r');
                app.LocationSpinner.Value = double(X);
                app.LocationSlider.Value = double(X);
            end
            set(app.CrossSectionIm,'HitTest','off')
            set(app.PosLine,'HitTest','off')
            app.CrossSectionWindowSlider.Value = app.UIAxesCrossSection.CLim;
            %app.UIAxesProjection.ButtonDownFcn = f;
            
        end


        function results = update_contrast_proj(app, lims)
            if ~isempty(app.ProjectionData)
                app.UIAxesProjection.CLim = lims;
            end
        end
    
        function results = update_contrast_cross(app, lims)
            if ~isempty(app.CrossSectionData)
                app.UIAxesCrossSection.CLim = lims;
            end
        end

    end

    

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            
        end

        % Button pushed function: LoadButton
        function LoadButtonPushed(app, event)

            wholeEyeDataPath = 'C:\Users\TeleOCT\Documents\Whole Eye Data';
            [fileName, pathName] = uigetfile({'*.npy','*.dcm'}, 'Pick .npy or .dicom file...', wholeEyeDataPath);
            
            app.OutputTextArea.Value = "Loading...";
            drawnow()
        
            [fp, fn, ext] = fileparts(fileName);
            if isequal(ext, '.npy')
                app.Data = mat2gray(single(OctReader.readNPY([pathName,fileName]))); % B-scans of phantom
            elseif isequal(ext, '.dcm')
                app.DicomInfo = dicominfo([pathName,fileName]);
                app.Data = dicomread([pathName,fileName]);
            else
                app.OutputTextArea.Value = "Load failed";
                return
            end
            app.OutputTextArea.Value = "Loaded!";
            app.load_init()
            app.update_projection()
        end

        % Button down function: UIAxesProjection
        function UIAxesProjectionButtonDown(app, event)
            app.OutputTextArea.Value = "Clicked";
            drawnow()
            point = app.UIAxesProjection.CurrentPoint;
            pointX = int32(round(point(1, 1)));
            pointY = int32(round(point(1, 2)));
            app.OutputTextArea.Value = sprintf("X: %d, Y: %d", pointX, pointY);
            drawnow()
            app.update_cross_section(pointX, pointY)
            
        end

        % Value changed function: LocationSpinner
        function LocationSpinnerValueChanged(app, event)

            value = app.LocationSpinner.Value;
            app.update_cross_section(value, value)
        end

        % Value changing function: LocationSlider
        function LocationSliderValueChanging(app, event)
            if app.CrossSectionUpdateMutex
                return
            end
            app.CrossSectionUpdateMutex = true;
            changingValue = event.Value;
            app.update_cross_section(changingValue, changingValue)
            app.CrossSectionUpdateMutex = false;
        end

        % Value changing function: ProjectionWindowSlider
        function ProjectionWindowSliderValueChanging(app, event)
            changingValue = event.Value;
            app.update_contrast_proj(changingValue)
        end

        % Value changing function: CrossSectionWindowSlider
        function CrossSectionWindowSliderValueChanging(app, event)
            changingValue = event.Value;
            if isempty(app.Data)
                return
            end
            app.update_projection();
            app.CrossSectionData = [];
            app.update_cross_section(1,1);
        end

        % Selection changed function: ProjectionDirectionButtonGroup
        function ProjectionDirectionButtonGroupSelectionChanged(app, event)
            selectedButton = app.ProjectionDirectionButtonGroup.SelectedObject;
            if isempty(app.Data)
                return
            end
            app.update_projection();
            app.CrossSectionData = [];
            app.update_cross_section(1,1);
        end

        % Selection changed function: ProjectionTypeButtonGroup
        function ProjectionTypeButtonGroupSelectionChanged(app, event)
            selectedButton = app.ProjectionTypeButtonGroup.SelectedObject;
            if isempty(app.Data)
                return
            end
            app.update_projection();
            app.CrossSectionData = [];
            app.update_cross_section(1,1);
        end

        % Value changed function: ZCroppingSlider
        function ZCroppingSliderValueChanged(app, event)

            value = app.ZCroppingSlider.Value;
            app.update_projection()
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 1637 1015];
            app.UIFigure.Name = 'MATLAB App';

            % Create LocationSlider
            app.LocationSlider = uislider(app.UIFigure);
            app.LocationSlider.Limits = [1 2];
            app.LocationSlider.MajorTicks = [1 2];
            app.LocationSlider.ValueChangingFcn = createCallbackFcn(app, @LocationSliderValueChanging, true);
            app.LocationSlider.Step = 1;
            app.LocationSlider.Position = [202 31 1414 3];
            app.LocationSlider.Value = 1;

            % Create ProjectionDirectionButtonGroup
            app.ProjectionDirectionButtonGroup = uibuttongroup(app.UIFigure);
            app.ProjectionDirectionButtonGroup.SelectionChangedFcn = createCallbackFcn(app, @ProjectionDirectionButtonGroupSelectionChanged, true);
            app.ProjectionDirectionButtonGroup.Title = 'Projection Direction';
            app.ProjectionDirectionButtonGroup.Position = [361 81 132 94];

            % Create EnFaceCoronalButton
            app.EnFaceCoronalButton = uiradiobutton(app.ProjectionDirectionButtonGroup);
            app.EnFaceCoronalButton.Text = 'En-Face/Coronal';
            app.EnFaceCoronalButton.Position = [11 48 113 22];
            app.EnFaceCoronalButton.Value = true;

            % Create SaggitalButton
            app.SaggitalButton = uiradiobutton(app.ProjectionDirectionButtonGroup);
            app.SaggitalButton.Text = 'Saggital';
            app.SaggitalButton.Position = [11 26 65 22];

            % Create AxialButton
            app.AxialButton = uiradiobutton(app.ProjectionDirectionButtonGroup);
            app.AxialButton.Text = 'Axial';
            app.AxialButton.Position = [11 4 65 22];

            % Create LoadButton
            app.LoadButton = uibutton(app.UIFigure, 'push');
            app.LoadButton.ButtonPushedFcn = createCallbackFcn(app, @LoadButtonPushed, true);
            app.LoadButton.Position = [36 112 83 41];
            app.LoadButton.Text = 'Load';

            % Create ProjectionTypeButtonGroup
            app.ProjectionTypeButtonGroup = uibuttongroup(app.UIFigure);
            app.ProjectionTypeButtonGroup.SelectionChangedFcn = createCallbackFcn(app, @ProjectionTypeButtonGroupSelectionChanged, true);
            app.ProjectionTypeButtonGroup.Title = 'Projection Type';
            app.ProjectionTypeButtonGroup.Position = [211 81 132 94];

            % Create SVPButton
            app.SVPButton = uiradiobutton(app.ProjectionTypeButtonGroup);
            app.SVPButton.Text = 'SVP';
            app.SVPButton.Position = [11 48 46 22];
            app.SVPButton.Value = true;

            % Create MIPButton
            app.MIPButton = uiradiobutton(app.ProjectionTypeButtonGroup);
            app.MIPButton.Text = 'MIP';
            app.MIPButton.Position = [11 26 43 22];

            % Create OutputTextAreaLabel
            app.OutputTextAreaLabel = uilabel(app.UIFigure);
            app.OutputTextAreaLabel.HorizontalAlignment = 'right';
            app.OutputTextAreaLabel.Position = [1295 148 41 22];
            app.OutputTextAreaLabel.Text = 'Output';

            % Create OutputTextArea
            app.OutputTextArea = uitextarea(app.UIFigure);
            app.OutputTextArea.Editable = 'off';
            app.OutputTextArea.Position = [1351 72 258 100];

            % Create ViewersPanel
            app.ViewersPanel = uipanel(app.UIFigure);
            app.ViewersPanel.Title = 'Viewers';
            app.ViewersPanel.Position = [1 213 1638 802];

            % Create UIAxesCrossSection
            app.UIAxesCrossSection = uiaxes(app.ViewersPanel);
            title(app.UIAxesCrossSection, 'Cross Section')
            app.UIAxesCrossSection.Position = [779 11 847 763];

            % Create UIAxesProjection
            app.UIAxesProjection = uiaxes(app.ViewersPanel);
            title(app.UIAxesProjection, 'Projection')
            app.UIAxesProjection.ButtonDownFcn = createCallbackFcn(app, @UIAxesProjectionButtonDown, true);
            app.UIAxesProjection.Position = [11 11 769 763];

            % Create CrossSectionDirectionButtonGroup
            app.CrossSectionDirectionButtonGroup = uibuttongroup(app.UIFigure);
            app.CrossSectionDirectionButtonGroup.Title = 'Cross Section Direction';
            app.CrossSectionDirectionButtonGroup.Position = [522 81 151 94];

            % Create XButton
            app.XButton = uiradiobutton(app.CrossSectionDirectionButtonGroup);
            app.XButton.Text = 'X';
            app.XButton.Position = [11 48 30 22];
            app.XButton.Value = true;

            % Create YButton
            app.YButton = uiradiobutton(app.CrossSectionDirectionButtonGroup);
            app.YButton.Text = 'Y';
            app.YButton.Position = [11 26 30 22];

            % Create LocationSpinnerLabel
            app.LocationSpinnerLabel = uilabel(app.UIFigure);
            app.LocationSpinnerLabel.HorizontalAlignment = 'right';
            app.LocationSpinnerLabel.Position = [14 12 50 22];
            app.LocationSpinnerLabel.Text = 'Location';

            % Create LocationSpinner
            app.LocationSpinner = uispinner(app.UIFigure);
            app.LocationSpinner.Limits = [1 Inf];
            app.LocationSpinner.ValueChangedFcn = createCallbackFcn(app, @LocationSpinnerValueChanged, true);
            app.LocationSpinner.Position = [79 12 100 22];
            app.LocationSpinner.Value = 1;

            % Create ProjectionWindowSliderLabel
            app.ProjectionWindowSliderLabel = uilabel(app.UIFigure);
            app.ProjectionWindowSliderLabel.HorizontalAlignment = 'center';
            app.ProjectionWindowSliderLabel.WordWrap = 'on';
            app.ProjectionWindowSliderLabel.Position = [759 132 76 43];
            app.ProjectionWindowSliderLabel.Text = 'Projection Window';

            % Create ProjectionWindowSlider
            app.ProjectionWindowSlider = uislider(app.UIFigure, 'range');
            app.ProjectionWindowSlider.ValueChangingFcn = createCallbackFcn(app, @ProjectionWindowSliderValueChanging, true);
            app.ProjectionWindowSlider.Position = [840 162 401 3];

            % Create CrossSectionWindowSliderLabel
            app.CrossSectionWindowSliderLabel = uilabel(app.UIFigure);
            app.CrossSectionWindowSliderLabel.HorizontalAlignment = 'center';
            app.CrossSectionWindowSliderLabel.WordWrap = 'on';
            app.CrossSectionWindowSliderLabel.Position = [761 90 76 43];
            app.CrossSectionWindowSliderLabel.Text = 'Cross Section Window';

            % Create CrossSectionWindowSlider
            app.CrossSectionWindowSlider = uislider(app.UIFigure, 'range');
            app.CrossSectionWindowSlider.ValueChangingFcn = createCallbackFcn(app, @CrossSectionWindowSliderValueChanging, true);
            app.CrossSectionWindowSlider.Position = [842 120 401 3];

            % Create ZCroppingSliderLabel
            app.ZCroppingSliderLabel = uilabel(app.UIFigure);
            app.ZCroppingSliderLabel.HorizontalAlignment = 'center';
            app.ZCroppingSliderLabel.WordWrap = 'on';
            app.ZCroppingSliderLabel.Position = [760 48 76 43];
            app.ZCroppingSliderLabel.Text = 'Z-Cropping';

            % Create ZCroppingSlider
            app.ZCroppingSlider = uislider(app.UIFigure, 'range');
            app.ZCroppingSlider.ValueChangedFcn = createCallbackFcn(app, @ZCroppingSliderValueChanged, true);
            app.ZCroppingSlider.Position = [843 77 401 3];

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = OctReader_source

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            % Execute the startup function
            runStartupFcn(app, @startupFcn)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end