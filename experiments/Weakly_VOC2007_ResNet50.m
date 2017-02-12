figure('visible', 'off');
clear; close all; clc;
clear mex;
clear is_valid_handle; % to clear init_key
%run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'startup'));
%% -------------------- CONFIG --------------------
opts.caffe_version          = 'caffe';
opts.gpu_id                 = auto_select_gpu();
active_caffe_mex(opts.gpu_id, opts.caffe_version);

% model
model.solver_def_file       = fullfile(pwd, 'models', 'rfcn_prototxts', 'ResNet-50L_OHEM_res3a', ['solver_lr1_3.prototxt']);
model.test_net_def_file     = fullfile(pwd, 'models', 'rfcn_prototxts', 'ResNet-50L_OHEM_res3a', 'test.prototxt');
model.net_file              = fullfile(pwd, 'models', 'pre_trained_models', 'ResNet-50L', 'ResNet-50-model.caffemodel');
model.mean_image            = fullfile(pwd, 'models', 'pre_trained_models', 'mean_image');
model.extra_para            = fullfile(pwd, 'models', 'pre_trained_models', 'box_param.mat');
model.extra_para            = load(model.extra_para);

% cache name
opts.cache_name             = 'rfcn_WEAKLY_Res50';
% config
conf                        = rfcn_config_ohem('image_means', model.mean_image);
conf.classes                = model.extra_para.VOCopts.classes;
conf.per_class_sample       = 3;
box_param.bbox_means        = model.extra_para.bbox_means;
box_param.bbox_stds         = model.extra_para.bbox_stds;
conf.base_select            = [1, 2, 3, 4];
conf.debug                  = true;
conf.rng_seed               = 5;
max_epoch                   = 10;
step_epoch                  = 9;
conf.nms_config             = false;
opts.cache_name             = [opts.cache_name, '_per-', num2str(conf.per_class_sample), '_nms-', num2str(conf.nms_config), ...
                                                '_max_epoch', num2str(max_epoch), '_stepsize-', num2str(step_epoch), ...
                                                '_seed-', num2str(conf.rng_seed)];
% train/test data
fprintf('Loading dataset...')
dataset                     = [];
dataset                     = Dataset.voc2007_trainval_ss(dataset, 'train', conf.use_flipped);
dataset                     = Dataset.voc2007_test_ss(dataset, 'test', false);
fprintf('Done.\n');

fprintf('-------------------- TRAINING --------------------\n');
train_time                  = tic;
opts.rfcn_model             = weakly_train_final(conf, dataset.imdb_train, dataset.roidb_train, ...
                                'solver_def_file',  model.solver_def_file, ...
                                'net_file',         model.net_file, ...
								'test_def_file',    model.test_net_def_file, ...
								'max_epoch',        max_epoch, ...
								'step_epoch',       step_epoch, ...
                                'cache_name',       opts.cache_name, ...
                                'box_param',        box_param);
assert(exist(opts.rfcn_model, 'file') ~= 0, 'not found trained model');
train_time                  = toc(train_time);
config_save_path            = fullfile(pwd, 'output', 'weakly_cachedir', opts.cache_name, 'config.mat');
save(config_save_path, 'conf', 'opts', 'model', '-v7.3');

fprintf('-------------------- TESTING --------------------\n');
test_time                   = tic;
mAP                         = weakly_co_test_mAP(conf, dataset.imdb_test, dataset.roidb_test, ...
                                'net_defs',         {model.test_net_def_file}, ...
                                'net_models',       {opts.rfcn_model}, ...
                                'cache_name',       opts.cache_name,...
                                'test_iteration',   2,...
                                'ignore_cache',     true);
test_time                   = toc(test_time);
loc_dataset                 = Dataset.voc2007_trainval_ss([], 'train', false);
Corloc                      = weakly_co_test_Cor(conf, loc_dataset.imdb_train{1}, loc_dataset.roidb_train{1}, ...
                                'net_defs',         {model.test_net_def_file}, ...
                                'net_models',       {opts.rfcn_model}, ...
                                'cache_name',       opts.cache_name,...
                                'ignore_cache',     true);
fprintf('Training Cost : %.1f s, Test Cost : %.1f s, mAP : %.2f, Corloc : %.2f\n', train_time, test_time, mAP, Corloc);


fprintf('----------------------------------All Test-----------------------------\n');
imdbs_name          = cell2mat(cellfun(@(x) x.name, dataset.imdb_train,'UniformOutput', false));
test_iters          = [];
rfcn_model          = [];
for iter = 0:numel(conf.base_select)
  test_iters{end+1} = ['Loop_', num2str(iter)];
  rfcn_model{end+1} = fullfile(pwd, 'output', 'weakly_cachedir' , opts.cache_name, imdbs_name, [test_iters{end}, '_final.caffemodel']);
  assert(exist(rfcn_model{end}, 'file') ~= 0, 'not found trained model');
end
mAPs                = [];
for index = 1:numel(rfcn_model)
mAPs(index)         = weakly_co_test_mAP(conf, dataset.imdb_test, dataset.roidb_test, ...
                             'net_defs',         {model.test_net_def_file}, ...
                             'net_models',       rfcn_model(index), ...
                             'cache_name',       opts.cache_name,...
                             'test_iteration',   1,...
                             'log_prefix',       [test_iters{index}, '_'],...
                             'ignore_cache',     true);
end
