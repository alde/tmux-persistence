#!/usr/bin/env ruby

# Start - Configuration Variables
session_dir = "#{Dir.home}/.sessions"
max_stored_sessions = 5
files_to_roll = 3
# End - Configuration Variables

Dir::mkdir(session_dir) unless File.exists?(session_dir)

files = []
Dir.entries(session_dir).each do |e|
  if e !~ /^\./
    files << e
  end
end
files.sort!

if files.length > max_stored_sessions
  0.upto(files_to_roll - 1) do |index|
    File.delete( session_dir+ "/" + files[index] )
  end
  puts "Rotated stored sessions"
end

#%x[rm #{session_dir}/*-restore]

sessions = %x[tmux list-sessions -F "\#{session_name}"].split("\n")

sessions.each do |session_name|
  rawPaneList = %x[tmux list-panes -t #{session_name} -s -F "\#{window_index} \#{pane_index} \#{window_width} \#{window_height} \#{pane_width} \#{pane_height} \#{window_name} \#{pane_current_path} \#{pane_pid}"].split("\n")
  panes = []
  rawPaneList.each do |pane_line|
    temp_pane = pane_line.split(" ")
    panes << {
      window_index: Integer(temp_pane[0]),
      pane_index: Integer(temp_pane[1]),
      window_width: Integer(temp_pane[2]),
      window_height: Integer(temp_pane[3]),
      pane_width: Integer(temp_pane[4]),
      pane_height: Integer(temp_pane[5]),
      window_name: temp_pane[6],
      cwd: temp_pane[7],
      pid: temp_pane[8]
    }
  end

  session_script = ""
  panes.each do |pane|
    pane[:cmd] = %x[ps --no-headers -o cmd --ppid #{pane[:pid]}].delete("\n")
    pane[:cmd] = %x[ps --no-headers -o cmd #{pane[:pid]}].delete("\n").gsub(/^-/,"") unless pane[:cmd] != ""

    session_script << "tmux new-window -t $SESSION -a -n #{pane[:window_name]} \"cd #{pane[:cwd]} && #{pane[:cmd]}\"\n"

    if pane[:pane_index] > 0
      if pane[:pane_width] < pane[:window_width]
        session_script << "tmux join-pane -h -l #{pane[:pane_width]} -s $SESSION:#{pane[:window_index] +1}.0 -t $SESSION:#{pane[:window_index]}\n"
      else
        session_script << "tmux join-pane -v -l #{pane[:pane_height]} -s $SESSION:#{pane[:window_index] +1}.0 -t $SESSION:#{pane[:window_index]}\n"
      end
    end
  end

  File.open("#{session_dir}/#{session_name}-restore","w") {|f| f.write(%Q[
    #!/usr/bin/env bash
    SESSION=#{session_name}

    if [ -z $TMUX ]; then

      # if session already exists, attach
      tmux has-session -t $SESSION
      if [ $? -eq 0 ]; then
        echo \"Session $SESSION already exists. Attaching...\"
        tmux attach -t $SESSION
        exit 0;
      fi

      # make new session
      tmux new-session -d -s $SESSION

    #{session_script}

      # attach to new session
      tmux select-window -t $SESSION:1
      tmux attach-session -t $SESSION

    fi
  ])}
end
