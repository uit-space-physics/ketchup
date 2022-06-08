% ketchup_b6conv converts output files to large .mat files
%
% HG 2013-02-25

ccc=pwd;
[a0,a1]=system('uname -n'); [a0,a2]=system('ps |grep -i matlab');
dummy=[a1 a2 datestr(now)];
dummy=dummy(double(dummy)~=10); dummy=dummy(double(dummy)~=32);

if ~exist('absolutelynomessages')
  absolutelynomessages=logical(0);
end

% ------- input data ------- %
% The easiest way to get the general parameters
inputb6;

% If the fields_per_file parameter wasn't defined in the input file,
% default to 1 field per file.
if ~exist('fields_per_file')
  fields_per_file = 1;
end

% Now read the species specific data
particle=struct();
fid=fopen('inputb6.m');
for ii=1:Nspecies
  theline=fgetl(fid);
  if length(theline)<5,
    theline=[theline '     '];
  end
  while ~(strcmp(theline(1:5),'%SPEC') | strcmp(theline(1:5),'%spec'))
    theline=fgetl(fid);
    if length(theline)<5,
      theline=[theline '     '];
    end
  end
  while ~(strcmp(theline(1:4),'%END') | strcmp(theline(1:4),'%end'))
    eval(theline)
    theline=fgetl(fid);
    if length(theline)<4,
      theline=[theline '    '];
    end
  end
  particle(ii).Nvz=Nvz;
  particle(ii).vzmin=vzmin;
  particle(ii).vzmax=vzmax;
  particle(ii).Nmu=Nmu;
  particle(ii).mumin=mumin;
  particle(ii).mumax=mumax;
  particle(ii).muexp=muexp;
  particle(ii).mass=mass;
  particle(ii).charge=charge;
  particle(ii).n0=n0;
  particle(ii).vz0=vz0;
  particle(ii).kTz=kTz;
  particle(ii).kTp=kTp;
  particle(ii).n0L=n0L;
  particle(ii).vz0L=vz0L;
  particle(ii).kTzL=kTzL;
  particle(ii).kTpL=kTpL;
  particle(ii).n0R=n0R;
  particle(ii).vz0R=vz0R;
  particle(ii).kTzR=kTzR;
  particle(ii).kTpR=kTpR;
end
fclose(fid);

% Find the number of processors used from the job.bat file, if there is one. 
if exist([pwd '/job.bat'])
  fid=fopen('job.bat');
  theline=fgetl(fid);
  while isempty(strfind(theline,'Nprocs')) & ...
        (isempty(strfind(theline,'PBS')) | ...
         isempty(strfind(theline,'-l')) | ...
         isempty(strfind(theline,'nodes')) )
    theline=fgetl(fid);
    if ~ischar(theline), break, end
  end
  fclose(fid);
  if ~isempty(strfind(theline,'Nprocs'))
    eval([theline(strfind(theline,'Nprocs'):end) ';'])
    Nprocsref=Nprocs;
    clear Nprocs
  elseif ~isempty(strfind(theline,'nodes'))
    eval([theline(strfind(theline,'nodes'):end) ';'])
    Nprocs=nodes;
    Nprocsref=Nprocs;
    clear Nprocs
  else
    Nprocsref=NaN;
  end
else
  Nprocsref=NaN;
end

% construct xi-vectors
dxi=1/Nz;
xicorn=dxi*[0:Nz];
xi=0.5*(xicorn(1:end-1) + xicorn(2:end));
% compute transformation, i.e. z-vectors and g'
aa=load(transffilename);
UHPpole  = aa(:,1) + 1i*aa(:,2);
UHPresid = aa(:,3) + 1i*aa(:,4);
[z,gp] = ketchup_b2transform(UHPpole,UHPresid,xi,zmin,zmax);
zcorn = ketchup_b2transform(UHPpole,UHPresid,xicorn,zmin,zmax);
dz    = diff(zcorn);

for ii=1:Nspecies
  particle(ii).dvz=(particle(ii).vzmax-particle(ii).vzmin)/particle(ii).Nvz;
  particle(ii).vzcorn=particle(ii).vz0 + ...
      particle(ii).vzmin + particle(ii).dvz*[0:particle(ii).Nvz];
  particle(ii).vz = ...
      0.5*(particle(ii).vzcorn(1:end-1)+particle(ii).vzcorn(2:end));

  vmu=[1:particle(ii).Nmu];
  particle(ii).mu = particle(ii).mumin + ...
      0.5*((vmu.^particle(ii).muexp+(vmu-1).^particle(ii).muexp) / ...
           particle(ii).Nmu^particle(ii).muexp) * ...
      (particle(ii).mumax-particle(ii).mumin);
  particle(ii).dmu = ((vmu.^particle(ii).muexp - ...
                       (vmu-1).^particle(ii).muexp) / ...
                      particle(ii).Nmu^particle(ii).muexp) * ...
      (particle(ii).mumax-particle(ii).mumin);
  particle(ii).mucorn = particle(ii).mu-0.5*particle(ii).dmu; 
  particle(ii).mucorn = [particle(ii).mucorn particle(ii).mu(end) + ...
                      0.5*particle(ii).dmu(end)];
end

cd outp

%% --- g --- %
% Prevent two processes from performing simultaneous conversions
if exist([pwd '/datfiles/lock.g'])
  if ~absolutelynomessages
    disp('Another process is already working on this directory.')
    disp('If this is not the case, remove the file')
    disp([pwd '/datfiles/lock.g'])
  end
else
  all_is_fine=logical(0);
  try
    dlmwrite('datfiles/lock.g',dummy,'');
    fid=fopen('datfiles/lock.g','r');
    lock=textscan(fid,'%s');
    fclose(fid);
    if strcmp(dummy,lock{1})
      all_is_fine=logical(1);
    end
  catch
    all_is_fine=logical(0);
  end

  if all_is_fine
    % The action is put inside this try block. The purpose of this is that if
    % an error happens after the writing of the lock file, this lock file
    % shall be removed so that future attempts are not blocked.
    try

      if exist([pwd '/datfiles/g/g.ketchup.dat'])
        % Load transformed vectors as generated by ketchup for comparison with
        % those computed here.
        % To prevent attempts to process files that are being written we
        % first wait ten seconds.
        pause(10)
        ginput = load('datfiles/g/g.ketchup.dat');
        zcmp = ginput(:,1).';
        gpcmp = ginput(:,2).';
        % Check if the transformation is the same.
        reldevz = (zcmp-z)./z;
        reldevgp = (gpcmp-gp)./gp;
        if max(abs(reldevz))>1e-6 |  max(abs(reldevgp))>1e-6
          error(['Transformation missmatch! ' ...
                 'max(abs(reldevz))=' num2str(max(abs(reldevz))) ...
                 ', max(abs(reldevgp))=' num2str(max(abs(reldevgp)))])
        end
        % Save all transformed vectors, both locally computed and of ketchup
        % origin. 
        save -v7.3 g.mat zcmp gpcmp z gp zcorn dz
        delete('datfiles/g/g.ketchup.dat')
      else
        pause(0.5)
      end
      delete('datfiles/lock.g')
    catch
      felfelfel=lasterror;
      disp(felfelfel.message)
      delete('datfiles/lock.g')
    end % end try
  end
end % end if exist('datfiles/lock.g')


%% --- B-field --- %
% Prevent two processes from performing simultaneous conversions
if exist([pwd '/datfiles/lock.Bfield'])
  if ~absolutelynomessages
    disp('Another process is already working on this directory.')
    disp('If this is not the case, remove the file')
    disp([pwd '/datfiles/lock.Bfield'])
  end
else
  all_is_fine=logical(0);
  try
    dlmwrite('datfiles/lock.Bfield',dummy,'')
    fid=fopen('datfiles/lock.Bfield','r');
    lock=textscan(fid,'%s');
    fclose(fid);
    if strcmp(dummy,lock{1})
      all_is_fine=logical(1);
    end
  catch
    all_is_fine=logical(0);
  end

  if all_is_fine
    try
      dd=dir('datfiles/Bfield');
      numbers=[];Nprocs=0;
      for ii=3:length(dd)
        if length(dd(ii).name)>=23
          if strcmp(dd(ii).name(1:6),'Bfield') & ...
                strcmp(dd(ii).name(12:end),'.ketchup.dat')
            procid = str2num(dd(ii).name(8:11));
            Nprocs = max(Nprocs,procid);
            if procid == 0
              numbers=ii;
            end
          end
        end
      end
      Nprocs = Nprocs + 1; % Numbers from 0 to Nprocs-1
      
      if length(numbers)>0 & ~(Nprocs<Nprocsref)

        % To prevent attempts to process files that are being written we
        % first wait ten seconds.
%         pause(10)

        Binput = [];
        for jj = 0:Nprocs-1
          Binput = [Binput; load(['datfiles/Bfield/' ...
                              dd(numbers).name(1:7) num2str(jj,'%0.4d') ...
                              '.ketchup.dat'])];
        end
        B  = Binput(:,1);
        dB = Binput(:,2);
        save -v7.3 Bfield.mat B dB particle Nz dz zcorn z dt 
        delete(['datfiles/Bfield/' dd(numbers).name(1:7) '*.ketchup.dat'])
        if ~absolutelynomessages
          disp('Bfield: done!')
        end
      else
        pause(0.5)
      end
      delete('datfiles/lock.Bfield')
    catch
      felfelfel=lasterror;
      disp(felfelfel.message)
      delete('datfiles/lock.Bfield')
    end % end try
  end
end % end if exist('datfiles/lock.Bfield')


%% --- Gravitational field --- %
% Prevent two processes from performing simultaneous conversions
if exist([pwd '/datfiles/lock.gravity'])
  if ~absolutelynomessages
    disp('Another process is already working on this directory.')
    disp('If this is not the case, remove the file')
    disp([pwd '/datfiles/lock.gravity'])
  end
else
  all_is_fine=logical(0);
  try
    dlmwrite('datfiles/lock.gravity',dummy,'')
    fid=fopen('datfiles/lock.gravity','r');
    lock=textscan(fid,'%s');
    fclose(fid);
    if strcmp(dummy,lock{1})
      all_is_fine=logical(1);
    end
  catch
    all_is_fine=logical(0);
  end

  if all_is_fine
    try
      dd=dir('datfiles/gravity');
      numbers=[];Nprocs=0;
      for ii=3:length(dd)
        if length(dd(ii).name)>=24
          if strcmp(dd(ii).name(1:7),'gravity') & ...
                strcmp(dd(ii).name(13:end),'.ketchup.dat')
            procid = str2num(dd(ii).name(9:12));
            Nprocs = max(Nprocs,procid);
            if procid == 0
              numbers=ii;
            end
          end
        end
      end
      Nprocs = Nprocs + 1; % Numbers from 0 to Nprocs-1

      if length(numbers)>0 & ~(Nprocs<Nprocsref)

        % To prevent attempts to process files that are being written we
        % first wait ten seconds.
%         pause(10)

        gravityinput = [];
        for jj = 0:Nprocs-1
          gravityinput = [gravityinput; load(['datfiles/gravity/' ...
                              dd(numbers).name(1:8) ...
                              num2str(jj,'%0.4d') '.ketchup.dat'])];
        end
        gravity  = gravityinput;
        save -v7.3 gravity.mat gravity particle Nz dz zcorn z dt 
        delete(['datfiles/gravity/' dd(numbers).name(1:8) '*.ketchup.dat'])
        if ~absolutelynomessages
          disp('Gravity: done!')
        end    
      else
        pause(0.5)
      end
      delete('datfiles/lock.gravity')
    catch
      felfelfel=lasterror;
      disp(felfelfel.message)
      delete('datfiles/lock.gravity')
    end % end try
  end
end % end if exist('datfiles/lock.gravity')


%% --- E-field --- %
% Prevent two processes from performing simultaneous conversions
if exist([pwd '/datfiles/lock.Efield'])
  if ~absolutelynomessages
    disp('Another process is already working on this directory.')
    disp('If this is not the case, remove the file')
    disp([pwd '/datfiles/lock.Efield'])
  end
else
  all_is_fine=logical(0);
  try
    dlmwrite('datfiles/lock.Efield',dummy,'')
    fid=fopen('datfiles/lock.Efield','r');
    lock=textscan(fid,'%s');
    fclose(fid);
    if strcmp(dummy,lock{1})
      all_is_fine=logical(1);
    end
  catch
    all_is_fine=logical(0);
  end

  if all_is_fine
    try
      dd=dir('datfiles/Efield');
      numbers=[];Nprocs=0;
      for ii=3:length(dd)
        if length(dd(ii).name)>=39
          if strcmp(dd(ii).name(1:6),'Efield') & ...
                strcmp(dd(ii).name(28:end),'.ketchup.dat')
            procid = str2num(dd(ii).name(24:27));
            Nprocs = max(Nprocs,procid);
            if procid == 0
              numbers=[numbers ii];
            end
          end
        end
      end
      Nprocs = Nprocs + 1; % Numbers from 0 to Nprocs-1

      % To prevent attempts to process files that are being written we wait
      % ten seconds if there are less than three time steps to process.
      if length(numbers)<3 & length(numbers)>0 & ~(Nprocs<Nprocsref)
        pause(10)
      end

      Efieldmatrix=[]; timestepsEfield=[];
      if length(numbers)>0 & ~(Nprocs<Nprocsref)
        EfieldInExistence=logical(0);
        if exist([pwd '/Efield.mat'])
          EfieldInExistence=logical(1);
        end
        if EfieldInExistence
          load('Efield.mat')
          hightimes=[];
          for ii=1:length(numbers)
            hightimes(ii)=str2num(dd(numbers(ii)).name(16:22));
          end
          newnumbers=numbers(hightimes>timestepsEfield(end));
          for ii=1:length(newnumbers)
            E = [];
            for jj = 0:Nprocs-1
              infile = ['datfiles/Efield/' dd(newnumbers(ii)).name(1:22) ...
                        'p' num2str(jj,'%0.4d') '.ketchup.dat'];
              fid=fopen(infile,'r');
              if fid<0
                error(['Error reading file ' infile])
              end
              Ein=[];timestamps=[];
              for kk=1:fields_per_file
                instruct = textscan(fid,'%*s%*s%f',1);
                if isempty(instruct{1}), break, end
                if instruct{1}<=timestepsEfield(end)
                  instruct = textscan(fid,'%f');
                else
                  timestamps=[timestamps instruct{1}];
                  instruct = textscan(fid,'%f');
                  Ein=[Ein instruct{1}];
                end
              end
              E = [E ; Ein];
              fclose(fid);
            end
            timestepsEfield = [timestepsEfield timestamps];
            Efieldmatrix = [Efieldmatrix; E.'];
            
            if ~absolutelynomessages
              disp([dd(newnumbers(ii)).name(1:22) ...
                    ' (' num2str(ii) '/' num2str(length(newnumbers)) ')'])
            end
          end
        else
          for ii=1:length(numbers)
            E = [];
            for jj = 0:Nprocs-1
              infile = ['datfiles/Efield/' dd(numbers(ii)).name(1:22) ...
                        'p' num2str(jj,'%0.4d') '.ketchup.dat'];
              fid=fopen(infile,'r');
              if fid<0
                error(['Error reading file ' infile])
              end
              Ein=[];timestamps=[];
              for kk=1:fields_per_file
                instruct = textscan(fid,'%*s%*s%f',1);
                if isempty(instruct{1}), break, end
                timestamps=[timestamps instruct{1}];
                instruct = textscan(fid,'%f');
                Ein=[Ein instruct{1}];
              end
              E = [E ; Ein];
              fclose(fid);
            end
            timestepsEfield = [timestepsEfield timestamps];
            Efieldmatrix = [Efieldmatrix; E.'];
            
            if ~absolutelynomessages
              disp([dd(numbers(ii)).name(1:22) ...
                    ' (' num2str(ii) '/' num2str(length(numbers)) ')'])
            end
          end
        end

        if EfieldInExistence
          [SUCCESS,MESSAGE,MESSAGEID]=copyfile('Efield.mat','Efield.mat.bak');
          if SUCCESS == 0
            system('cp Efield.mat Efield.mat.bak');
          end
        end
        save -v7.3 Efield.mat Efieldmatrix timestepsEfield particle ...
            Nz dz zcorn z dt Niter dump_period_distr ...
            dump_period_fields dump_start shift_test_period zmin zmax ...
            Nspecies voltage
        if EfieldInExistence
          delete('Efield.mat.bak');
        end
        if ~absolutelynomessages
          disp('saved Efield.mat')
        end

        clear Efieldmatrix
        for ii=1:length(numbers)
          delete(['datfiles/Efield/Efield' dd(numbers(ii)).name(7:23) ...
                  '*.ketchup.dat']);
        end
        if ~absolutelynomessages
          disp('Efield: done!')
        end
      else
        pause(0.5)
      end
      delete('datfiles/lock.Efield')
    catch
      felfelfel=lasterror;
      disp(felfelfel.message)
      delete('datfiles/lock.Efield')
    end % end try
  end
end % end if exist('datfiles/lock.Efield')


%% --- Current --- %
% Prevent two processes from performing simultaneous conversions
if exist([pwd '/datfiles/lock.current'])
  if ~absolutelynomessages
    disp('Another process is already working on this directory.')
    disp('If this is not the case, remove the file')
    disp([pwd '/datfiles/lock.current'])
  end
else
  all_is_fine=logical(0);
  try
    dlmwrite('datfiles/lock.current',dummy,'')
    fid=fopen('datfiles/lock.current','r');
    lock=textscan(fid,'%s');
    fclose(fid);
    if strcmp(dummy,lock{1})
      all_is_fine=logical(1);
    end
  catch
    all_is_fine=logical(0);
  end

  if all_is_fine
    try
      dd=dir('datfiles/current');
      numbers=[];Nprocs=0;
      for ii=3:length(dd)
        if length(dd(ii).name)>=40
          if strcmp(dd(ii).name(1:7),'current') & ...
                strcmp(dd(ii).name(29:end),'.ketchup.dat')
            procid = str2num(dd(ii).name(25:28));
            Nprocs = max(Nprocs,procid);
            if procid == 0
              numbers=[numbers ii];
            end
          end
        end
      end
      Nprocs = Nprocs + 1; % Numbers from 0 to Nprocs-1

      % To prevent attempts to process files that are being written we wait
      % ten seconds if there are less than three time steps to process.
      if length(numbers)<3 & length(numbers)>0 & ~(Nprocs<Nprocsref)
        pause(10)
      end
%%%
      currentmatrix=[]; timestepscurrent=[];
      if length(numbers)>0 & ~(Nprocs<Nprocsref)
        currentInExistence=logical(0);
        if exist([pwd '/current.mat'])
          currentInExistence=logical(1);
        end
        if currentInExistence
          load('current.mat')
          hightimes=[];
          for ii=1:length(numbers)
            hightimes(ii)=str2num(dd(numbers(ii)).name(17:23));
          end
          newnumbers=numbers(hightimes>timestepscurrent(end));
          for ii=1:length(newnumbers)
            I = [];
            for jj = 0:Nprocs-1
              infile = ['datfiles/current/' dd(newnumbers(ii)).name(1:23) ...
                        'p' num2str(jj,'%0.4d') '.ketchup.dat'];
              fid=fopen(infile,'r');
              if fid<0
                error(['Error reading file ' infile])
              end
              Iin=[];timestamps=[];
              for kk=1:fields_per_file
                instruct = textscan(fid,'%*s%*s%f',1);
                if isempty(instruct{1}), break, end
                if instruct{1}<=timestepscurrent(end)
                  instruct = textscan(fid,'%f');
                else
                  timestamps=[timestamps instruct{1}];
                  instruct = textscan(fid,'%f');
                  Iin=[Iin instruct{1}];
                end
              end
              I = [I ; Iin];
              fclose(fid);
            end
            timestepscurrent = [timestepscurrent timestamps];
            currentmatrix = [currentmatrix; I.'];
            
            if ~absolutelynomessages
              disp([dd(newnumbers(ii)).name(1:23) ...
                    ' (' num2str(ii) '/' num2str(length(newnumbers)) ')'])
            end
          end
        else
          for ii=1:length(numbers)
            I = [];
            for jj = 0:Nprocs-1
              infile = ['datfiles/current/' dd(numbers(ii)).name(1:23) ...
                        'p' num2str(jj,'%0.4d') '.ketchup.dat'];
              fid=fopen(infile,'r');
              if fid<0
                error(['Error reading file ' infile])
              end
              Iin=[];timestamps=[];
              for kk=1:fields_per_file
                instruct = textscan(fid,'%*s%*s%f',1);
                if isempty(instruct{1}), break, end
                timestamps=[timestamps instruct{1}];
                instruct = textscan(fid,'%f');
                Iin=[Iin instruct{1}];
              end
              I = [I ; Iin];
              fclose(fid);
            end
            timestepscurrent = [timestepscurrent timestamps];
            currentmatrix = [currentmatrix; I.'];
            
            if ~absolutelynomessages
              disp([dd(numbers(ii)).name(1:23) ...
                    ' (' num2str(ii) '/' num2str(length(numbers)) ')'])
            end
          end
        end
%%%
        if currentInExistence
          [SUCCESS,MESSAGE,MESSAGEID]=copyfile('current.mat','current.mat.bak');
          if SUCCESS == 0
            system('cp current.mat current.mat.bak');
          end
        end
        save -v7.3 current.mat currentmatrix timestepscurrent particle ...
            Nz dz zcorn z dt Niter dump_period_distr ...
            dump_period_fields dump_start shift_test_period zmin zmax ...
            Nspecies voltage
        if currentInExistence
          delete('current.mat.bak');
        end
        if ~absolutelynomessages
          disp('saved current.mat')
        end

        clear currentmatrix
        % EXTERMINATE!
        for ii=1:length(numbers)
          delete(['datfiles/current/current' dd(numbers(ii)).name(8:24) ...
                  '*.ketchup.dat']);
        end
        if ~absolutelynomessages
          disp('current: done!')
        end
      else
        pause(0.5)
      end
      delete('datfiles/lock.current')
    catch
      felfelfel=lasterror;
      disp(felfelfel.message)
      delete('datfiles/lock.current')
    end % end try
  end
end % end if exist('datfiles/lock.current')


%% --- density --- %
% Prevent two processes from performing simultaneous conversions
if exist([pwd '/datfiles/lock.density'])
  if ~absolutelynomessages
    disp('Another process is already working on this directory.')
    disp('If this is not the case, remove the file')
    disp([pwd '/datfiles/lock.density'])
  end
else
  all_is_fine=logical(0);
  try
    dlmwrite('datfiles/lock.density',dummy,'')
    fid=fopen('datfiles/lock.density','r');
    lock=textscan(fid,'%s');
    fclose(fid);
    if strcmp(dummy,lock{1})
      all_is_fine=logical(1);
    end
  catch
    all_is_fine=logical(0);
  end

  if all_is_fine
    try
      dd=dir('datfiles/density');
      numbers=[];Nprocs=0;
      for ii=3:length(dd)
        if length(dd(ii).name)>=40
          if strcmp(dd(ii).name(1:7),'density') & ...
                strcmp(dd(ii).name(29:end),'.ketchup.dat')
            procid = str2num(dd(ii).name(25:28));
            Nprocs = max(Nprocs,procid);
            if procid == 0
              numbers=[numbers ii];
            end
          end
        end
      end
      Nprocs = Nprocs + 1; % Numbers from 0 to Nprocs-1

      % To prevent attempts to process files that are being written we wait
      % ten seconds if there are less than three time steps to process.
      if length(numbers)<3 & length(numbers)>0 & ~(Nprocs<Nprocsref)
        pause(10)
      end

%%%%
      densitymatrix=[]; timestepsdensity=[];
      if length(numbers)>0 & ~(Nprocs<Nprocsref)
        densityInExistence=logical(0);
        if exist([pwd '/density.mat'])
          densityInExistence=logical(1);
        end
        if densityInExistence
          load('density.mat')
          hightimes=[];
          for ii=1:length(numbers)
            hightimes(ii)=str2num(dd(numbers(ii)).name(17:23));
          end
          newnumbers=numbers(hightimes>timestepsdensity(end));
          for ii=1:length(newnumbers)
            Dens = [];
            for jj = 0:Nprocs-1
              infile = ['datfiles/density/' dd(newnumbers(ii)).name(1:23) ...
                        'p' num2str(jj,'%0.4d') '.ketchup.dat'];
              fid=fopen(infile,'r');
              if fid<0
                error(['Error reading file ' infile])
              end
              Densin=[];timestamps=[];
              for kk=1:fields_per_file
                instruct = textscan(fid,'%*s%*s%f',1);
                if isempty(instruct{1}), break, end
                if instruct{1}<= timestepsdensity(end)
                  instruct = textscan(fid,'%f');
                else
                  timestamps=[timestamps instruct{1}];
                  instruct = textscan(fid,'%f');
                  Densin=cat(3,Densin,reshape(instruct{1},Nspecies, ...
                                      prod(size(instruct{1}))/Nspecies));
                end
              end
              Dens = cat(2,Dens, Densin);
              fclose(fid);
            end
            timestepsdensity = [timestepsdensity timestamps];
            densitymatrix=cat(3,densitymatrix,Dens);
            if ~absolutelynomessages
              disp([dd(newnumbers(ii)).name(1:23) ...
                    ' (' num2str(ii) '/' num2str(length(newnumbers)) ')'])
            end
          end
        else
          for ii=1:length(numbers)
            Dens = [];
            for jj = 0:Nprocs-1
              infile = ['datfiles/density/' dd(numbers(ii)).name(1:23) ...
                        'p' num2str(jj,'%0.4d') '.ketchup.dat'];
              fid=fopen(infile,'r');
              if fid<0
                error(['Error reading file ' infile])
              end
              Densin=[];timestamps=[];
              for kk=1:fields_per_file
                instruct = textscan(fid,'%*s%*s%f',1);
                if isempty(instruct{1}), break, end
                timestamps=[timestamps instruct{1}];
                instruct = textscan(fid,'%f');
                Densin=cat(3,Densin,reshape(instruct{1},Nspecies, ...
                                            prod(size(instruct{1}))/Nspecies));
              end
              Dens = cat(2,Dens, Densin);
              fclose(fid);
            end
            timestepsdensity = [timestepsdensity timestamps];
            densitymatrix=cat(3,densitymatrix,Dens);

            if ~absolutelynomessages
              disp([dd(numbers(ii)).name(1:23) ...
                    ' (' num2str(ii) '/' num2str(length(numbers)) ')'])
            end
          end
        end
%%%%
        if densityInExistence
          [SUCCESS,MESSAGE,MESSAGEID]=copyfile('density.mat','density.mat.bak');
          if SUCCESS == 0
            system('cp density.mat density.mat.bak');
          end
        end
        save -v7.3 density.mat densitymatrix timestepsdensity particle ...
            Nz dz zcorn z dt Niter dump_period_distr ...
            dump_period_fields dump_start shift_test_period zmin zmax ...
            Nspecies voltage
        if densityInExistence
          delete('density.mat.bak');
        end
        if ~absolutelynomessages
          disp('saved density.mat')
        end

        clear densitymatrix
        % EXTERMINATE!
        for ii=1:length(numbers)
          delete(['datfiles/density/density' dd(numbers(ii)).name(8:15) ...
                  '*.ketchup.dat']);
        end
        if ~absolutelynomessages
          disp('density: done!')
        end
      else
        pause(0.5)
      end
      delete('datfiles/lock.density')
    catch
      felfelfel=lasterror;
      disp(felfelfel.message)
      delete('datfiles/lock.density')
    end % end try
  end
end % end if exist('datfiles/lock.density')


%% --- distribution function f(z,vz,mu) --- %
% one file per timestep, containing a structured array of all species,
% with a three-dimensional array for f(z,vz,mu) in each.

% Prevent two processes from performing simultaneous conversions
if exist([pwd '/datfiles/lock.fzvzmu'])
  if ~absolutelynomessages
    disp('Another process is already working on this directory.')
    disp('If this is not the case, remove the file')
    disp([pwd '/datfiles/lock.fzvzmu'])
  end
else
  all_is_fine=logical(0);
  try
    dlmwrite('datfiles/lock.fzvzmu',dummy,'')
    fid=fopen('datfiles/lock.fzvzmu','r');
    lock=textscan(fid,'%s');
    fclose(fid);
    if strcmp(dummy,lock{1})
      all_is_fine=logical(1);
    end
  catch
    all_is_fine=logical(0);
  end

  if all_is_fine
    try
      dd=dir('datfiles/fzvzmu');
      fzvzmustruct=struct();
      for ii=1%:Nspecies                          %%%%%%%%%%%%%%%%%%%%%%%%%
        fzvzmustruct(ii).timestep=0;
      end

      % pick out the files containing species 1 and process 0. 
      % Then start the loop.
      for speciesnumber=1%Nspecies:-1:1           %%%%%%%%%%%%%%%%%%%%%%%%%
        if ~isnan(particle(speciesnumber).mass) & ...
              ~isinf(particle(speciesnumber).mass)
          break
        end
      end
      startfiles=[];Nprocs=0;
      for ii=3:length(dd)
        if length(dd(ii).name)>=20
          if strcmp(dd(ii).name(1:6),'fzvzmu')
            if strcmp(dd(ii).name(15:16),num2str(speciesnumber,'%0.2d')) & ...
                  strcmp(dd(ii).name(22:end),'.ketchup.dat')
              procid = str2num(dd(ii).name(18:21));
              Nprocs = max(Nprocs,procid);
              if strcmp(dd(ii).name(17:21),'p0000')
                startfiles = [startfiles ii];
              end
            end
          end
        end
      end
      Nprocs = Nprocs + 1; % Numbers from 0 to Nprocs-1

      % To prevent attempts to process files that are being written we wait
      % twenty seconds if there are less than two time steps to process.
      if length(startfiles)<2 & length(startfiles)>0 & ~(Nprocs<Nprocsref)
%         pause(20)
      end

      if length(startfiles)>0 & ~(Nprocs<Nprocsref)
        for ii = startfiles
          % If not all files of the largest non-infinite mass species
          % number exist, that is an error
          infilesexistnot = logical(zeros(1,Nprocs));
          for jj = 0:Nprocs-1
            infilesexistnot(jj+1) = ...
                ~exist(['datfiles/fzvzmu/' dd(ii).name(1:14) ...
                        num2str(speciesnumber,'%0.2d') ...
                        'p' num2str(jj,'%0.4d') '.ketchup.dat']);
          end        
          if sum(infilesexistnot)>0
            error(['fzvzmu: infilesexistnot=',num2str(infilesexistnot)])
          end
        
          thistimestep=str2num(dd(ii).name(7:13));
          for thisspecies = 1%:Nspecies           %%%%%%%%%%%%%%%%%%%%%%%%%
            if ~isnan(particle(thisspecies).mass) & ...
                  ~isinf(particle(thisspecies).mass)
              fzvzmustruct(thisspecies).timestep=thistimestep;
              fzvzmustruct(thisspecies).f = ...
                  zeros(particle(thisspecies).Nvz,particle(thisspecies).Nmu,Nz);
              ivzoffset=[];fcounter=1;

              for jj = 0:Nprocs-1
                infile = ['datfiles/fzvzmu/' dd(ii).name(1:14) ...
                          num2str(thisspecies,'%0.2d') ...
                          'p' num2str(jj,'%0.4d') '.ketchup.dat'];
                fid=fopen(infile,'r');
                if fid<0
                  error(['Error reading file ' infile])
                end

                for kk = 1:Nz
                  instruct = textscan(fid,'%*s%*s%f',1);
                  if isempty(instruct{1}), break, end
                  ivzoffset=[ivzoffset instruct{1}];
                  instruct = textscan(fid,'%f');
                  fzvzmustruct(thisspecies).f(:,:,fcounter) = ...
                      reshape(instruct{1}, [particle(thisspecies).Nmu ...
                                      particle(thisspecies).Nvz]).';
                  fcounter = fcounter + 1;
                end
      
                fclose(fid);
              end
              fzvzmustruct(thisspecies).ivzoffset = ivzoffset;
            end
          end
  
          outfile = ['fzvzmu' num2str(thistimestep,'%0.7i') '.mat'];
          save(outfile,'-v7.3','fzvzmustruct','thistimestep','particle', ...
               'Nz','dz','zcorn','z','dt','Niter','dump_period_fields', ...
               'dump_period_distr','dump_start','shift_test_period', ...
               'zmin','zmax','Nspecies','voltage')

% $$$       system(['rm ' infile(1:30) '??p*.ketchup.dat']);
          delete([infile(1:30) '*p*.ketchup.dat']);

          if ~absolutelynomessages
            disp(['fzvzmu: timestep ' num2str(thistimestep) ' done!'])
          end
        end
      end
      clear fzvzmustruct
      delete('datfiles/lock.fzvzmu')
    catch
      felfelfel=lasterror;
      disp(felfelfel.message)
      delete('datfiles/lock.fzvzmu')
    end % end try
  end
end % end if exist('datfiles/lock.fzvzmu')


%% --- Reduced distribution files --- %
% pick out the files containing species 1 and process 0. 
% Then start the loop.

% Prevent two processes from performing simultaneous conversions
if exist([pwd '/datfiles/lock.fzvz'])
  if ~absolutelynomessages
    disp('Another process is already working on this directory.')
    disp('If this is not the case, remove the file')
    disp([pwd '/datfiles/lock.fzvz'])
  end
else
  all_is_fine=logical(0);
  try
    dlmwrite('datfiles/lock.fzvz',dummy,'')
    fid=fopen('datfiles/lock.fzvz','r');
    lock=textscan(fid,'%s');
    fclose(fid);
    if strcmp(dummy,lock{1})
      all_is_fine=logical(1);
    end
  catch
    all_is_fine=logical(0);
  end

  if all_is_fine
    try
      dd=dir('datfiles/fzvz');
      for speciesnumber=Nspecies:-1:1
        if ~isnan(particle(speciesnumber).mass) & ...
              ~isinf(particle(speciesnumber).mass)
          break
        end
      end
      startfiles=[];Nprocs=0;
      for ii=3:length(dd)
        if length(dd(ii).name)>=20
          if strcmp(dd(ii).name(1:4),'fzvz') & ...
                strcmp(dd(ii).name(20:end),'.ketchup.dat')
% $$$             if strcmp(dd(ii).name(13:14),'01')
            if strcmp(dd(ii).name(13:14),num2str(speciesnumber,'%0.2d'))
              procid = str2num(dd(ii).name(16:19));
              Nprocs = max(Nprocs,procid);
              if strcmp(dd(ii).name(15:19),'p0000')
                startfiles = [startfiles ii];
              end
            end
          end
        end
      end
      Nprocs = Nprocs + 1; % Numbers from 0 to Nprocs-1

      % To prevent attempts to process files that are being written we wait
      % ten seconds if there are less than two time steps to process.
      if length(startfiles)<2 & length(startfiles)>0
%         pause(10)
      end

      if length(startfiles)>0 & ~(Nprocs<Nprocsref)
        for ii = startfiles
          % If not all files for the largest non-infinite mass species
          % number exist, that is an error.
          infilesexistnot = logical(zeros(1,Nprocs));
          for jj = 0:Nprocs-1
            infilesexistnot(jj+1) = ...
                ~exist(['datfiles/fzvz/' dd(ii).name(1:12) ...
                        num2str(speciesnumber,'%0.2d') ...
                        'p' num2str(jj,'%0.4d') '.ketchup.dat']);
          end
          if sum(infilesexistnot)>0
            error(['fzvz: infilesexistnot=',num2str(infilesexistnot)])
          end

          thistimestep=str2num(dd(ii).name(5:11));
          for thisspecies = 1:Nspecies
            if ~isnan(particle(thisspecies).mass) & ...
                  ~isinf(particle(thisspecies).mass)
              fzvzstruct(thisspecies).timestep=thistimestep;
              fzvzstruct(thisspecies).f = ...
                  zeros(particle(thisspecies).Nvz,Nz);
              ivzoffset=[];fcounter=1;

              for jj = 0:Nprocs-1
                infile = ['datfiles/fzvz/' dd(ii).name(1:12) ...
                          num2str(thisspecies,'%0.2d') ...
                          'p' num2str(jj,'%0.4d') '.ketchup.dat'];
                fid=fopen(infile,'r');
                if fid<0
                  error(['Error reading file ' infile])
                end

                for kk = 1:Nz
                  instruct = textscan(fid,'%*s%*s%f',1);
                  if isempty(instruct{1}), break, end
                  ivzoffset=[ivzoffset instruct{1}];
                  instruct = textscan(fid,'%f');
                  fzvzstruct(thisspecies).f(:,fcounter) = instruct{1};
                  fcounter = fcounter + 1;
                end

                fclose(fid);
              end
              fzvzstruct(thisspecies).ivzoffset = ivzoffset;
            end
          end
  
          outfile = ['fzvz' num2str(thistimestep,'%0.7i') '.mat'];
          save(outfile,'-v7.3','fzvzstruct','thistimestep','particle', ...
               'Nz','dz','zcorn','z','dt','Niter','dump_period_fields', ...
               'dump_period_distr','dump_period_distr_1v','dump_start', ...
               'shift_test_period','zmin','zmax','Nspecies','voltage')

          % EXTERMINATE!
          delete([infile(1:26) '*p*.ketchup.dat']);
          if ~absolutelynomessages
            disp(['fzvz: timestep ' num2str(thistimestep) ' done!'])
          end
        end
      end
      delete('datfiles/lock.fzvz')
    catch
      felfelfel=lasterror;
      disp(felfelfel.message)
      delete('datfiles/lock.fzvz')
    end % end try
  end
end % end if exist('datfiles/lock.fzvz')


cd(ccc)