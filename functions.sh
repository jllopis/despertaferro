# Functions
function log() {
  echo -e "${information}$1${text_reset}"
  echo -e $@ >> $LOGFILE
}

function log_warn() {
  echo -e "${attention}$1${text_reset}"
  echo -e $@ >> $LOGFILE
}

function log_err () {
  echo -e "${failure}$1${text_reset}"
  echo -e $@ >> $LOGFILE
}

function log_ok () {
  echo -e "${success}$1${text_reset}"
  echo -e $@ >> $LOGFILE
}

function get_existing_dotfiles(){
  for file in $FILES; do
    DOTFILES+=($file)
    if [[ ( -r $HOME/.$file ) && ( ! -L $HOME/.$file ) ]]; then
      FILES2BACK+=($file)
    elif [[ -L $HOME/.$file ]]; then
      FILEISLINK+=($file)
    fi
  done
  unset file

  # Now for the directories
  for dir in $DIRS; do
    if [[ "$dir" == "despertaferro" || "$dir" == "bin" ]]; then continue; fi
    DOTDIRS+=($dir)
    if [[ ( -r $HOME/.$dir ) && ( ! -L $HOME/.$dir ) ]]; then
      DIRS2BACK+=($dir)
    elif [[ -L $HOME/.$dir ]]; then
      DIRISLINK+=($dir)
    fi
  done
  unset dir
}

function backup_dotfiles(){
  log "Backing up files and directories"

  BACKUP_FILE=$HOME/despertaferro_backup-$TIMESTAMP.tar

  get_existing_dotfiles
  
  if [[ ${#FILES2BACK[@]} -gt 0 ]]; then
    for file in ${FILES2BACK[@]} ; do
      log "Backing up ${filename}$file"
      tar -rvf $BACKUP_FILE $HOME/.$file >> $LOGFILE 2>&1
    done
  else
    log_warn "No files were found to backup"
  fi

  if [[ ${#DIRS2BACK[@]} -gt 0 ]]; then
    for dir in ${DIRS2BACK[@]} ; do
      log "Backing up directory ${filename}$dir"
      tar -rvf $BACKUP_FILE $HOME/.$dir >> $LOGFILE 2>&1
    done
  else
    log_warn "No directories were found to backup"
  fi

  # If backup file has been created, compress.
  # If it is zero size, delete
  if [[ -s $BACKUP_FILE ]]; then
    gzip $BACKUP_FILE
  elif [[ -z $BACKUP_FILE ]]; then
    rm $BACKUP_FILE
   log_err "We cannot create the backup file"
  fi

  if [[ ${#FILEISLINK[@]} -gt 0 ]]; then
    log "Found ${#FILEISLINK[@]} links to dotfiles. They will be relinked!"
  fi

  if [[ ${#DIRISLINK[@]} -gt 0 ]]; then
    log "Found ${#DIRISLINK[@]} links to dot directories. They will be relinked!"
  fi

  if [ ! -L $HOME/.gvimrc ]; then
    tar -rvf $BACKUP_FILE $HOME/.gvimrc >> $LOGFILE 2>&1
  fi
}

function clean_old(){
  for file in ${FILES2BACK[@]}; do
    rm $HOME/.$file
  done

  for file in ${FILEISLINK[@]}; do
    rm $HOME/.$file
  done

  for dir in ${DIRS2BACK[@]}; do
    rm -rf $HOME/.$dir
  done

  for dir in ${DIRISLINK[@]}; do
    rm $HOME/.$dir
  done

  if [ -r $HOME/.gvimrc ]; then
    rm $HOME/.gvimrc
  fi
}

function link_dotfiles () {
  log "Linking $despertaferro dotfiles to your home folder"
  for file in ${DOTFILES[@]} ${DOTDIRS[@]}; do
    SOURCE_FILE=$HOME/.despertaferro/despertaferro/$file
    TARGET_FILE=$HOME/.$file
    if [ -e $SOURCE_FILE ]; then
      echo "${notice}Linking ${hermes} ${package}$file ${notice}to $filename$HOME/.$file"
      ln -sf $SOURCE_FILE $TARGET_FILE
      if [ $? -ne 0 ]; then
        log_err "Could not link $SOURCE_FILE to $TARGET_FILE"
      fi
    fi
  done
}

function vim_install_submodules(){
  log "Installing submodules for vim. May take a while."
  pushd $APP_DIR &> /dev/null
  git submodule init && git submodule update &> /dev/null
  popd &> /dev/null
}

function install_or_update_homebrew() {
  # Check if homebrew is already installed
  brew --version &> /dev/null
  if [ $? -ne 0 ]; then
    # Homebrew is not installed, so we will install it
    log "Installing ${component}Homebrew"
    ruby -e "$(curl -fksSL https://raw.github.com/mxcl/homebrew/go)"
  else
    # Installed and running
    log "Your ${component}Homebrew ${information}appear to be OK. Using it!"
    # Use the last homebrew
    brew update &> /dev/null
    # Upgrade installed packages
    brew upgrade &> /dev/null
    # Some sanity
    brew cleanup &> /dev/null
  fi
}

# Manage Brew
function install_brew_package(){
  log "Installing ${package}$1"
  HOMEBREW_OUTPUT=`brew install $1 2>&1`
  if [[ "$?" != "0" ]]; then
    log_err "[$1] Homebrew had a problem ($HOMEBREW_OUTPUT)"
    exit 1
  fi
}

function brew_checkinstall () {
  brew list $1 &> /dev/null
  if [ $? == 0 ]; then
    log_ok "Your ${package}$1 ${success}installation is fine. Doing nothing"
  else
    install_brew_package $1
  fi
}

function remove_homebrew () {
  log "Removing homebrew recipe $1"
  HOMEBREW_OUTPUT=`brew uninstall $1 2>&1`
  handle_error $1 "Homebrew had a problem while removing\n($HOMEBREW_OUTPUT):"
}

# Package installation
brew_checkinstall_vim(){
  echo -e "${notice}Checking for a sane ${component}Vim ${notice}installation"
  SKIP=`vim --version | grep '+clipboard'`
  if [[ "$SKIP" == "" ]]; then
    brew list macvim &> /dev/null
    if [ $? == 0 ]; then
      log_warn "Removing Homebrew's macvim recipe"
      remove_homebrew "macvim"
    else
      log "You don't have Homebrew's macvim installed at all"
    fi
    install_brew_package "macvim --override-system-vim"
  else
    log_ok "Your Vim installation is fine. Doing nothing"
  fi
}

install_or_update(){
  for pack in ${PACKAGES[@]}; do
    if [[ "$THIS_OS" == "osx" ]]; then
      # Install with brew
      if [[ "$pack" == "vim" ]]; then brew_checkinstall_vim; continue; fi
      brew_checkinstall $pack
    elif [[ "$THIS_OS" == "linux" ]]; then
      # Install linux package (rpm based only)
      log "Trying to install $pack"
      sudo yum -y install $pack
    else
      # Not supported
      log_err "Your system is not supported. Can't install the packages"
      exit 1
    fi
  done
}

function install_asepsis(){
  log "Installing Asepsis"
  curl -OL http://downloads.binaryage.com/Asepsis-1.3.dmg
  if [[ -s "Asepsis-1.3.dmg" ]]; then
    hdiutil mount Asepsis-1.3.dmg
  else
    log_err "Asepsis could not be downloaded"
    return
  fi
  sudo installer -pkg /Volumes/Asepsis/Asepsis.mpkg -target /
  hdiutil unmount /Volumes/Asepsis
}

function configure_osx(){
# Credit to https://github.com/mathiasbynens/dotfiles/blob/master/.osx
  log "Configuring OSX"
  
  # Install Homebrew
  install_or_update_homebrew

  # Install Basic Homebrew packages (always install because they are outdated)
  brew_checkinstall coreutils
  #echo "Don’t forget to add $(brew --prefix coreutils)/libexec/gnubin to \$PATH."
  # Install GNU `find`, `locate`, `updatedb`, and `xargs`, g-prefixed
  brew_checkinstall findutils

  # We will going to set visibility for dotfiles. This will show the .DS_Store 
  # everywhere. We will install Asepsis to better manage them (http://asepsis.binaryage.com)
  install_asepsis
return
  # Menu bar: disable transparency
  defaults write NSGlobalDomain AppleEnableMenuBarTransparency -bool false

  # Menu bar: show remaining battery time (on pre-10.8); hide percentage
  defaults write com.apple.menuextra.battery ShowPercent -string "NO"
  defaults write com.apple.menuextra.battery ShowTime -string "YES"

  # Menu bar: hide the useless Time Machine and Volume icons
  defaults write com.apple.systemuiserver menuExtras -array "/System/Library/CoreServices/Menu Extras/Bluetooth.menu" "/System/Library/CoreServices/Menu Extras/AirPort.menu" "/System/Library/CoreServices/Menu Extras/Battery.menu" "/System/Library/CoreServices/Menu Extras/Clock.menu"

  # Set highlight color to green
  defaults write NSGlobalDomain AppleHighlightColor -string '0.764700 0.976500 0.568600'

  # Set sidebar icon size to medium
  defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 2

  # Always show scrollbars
  defaults write NSGlobalDomain AppleShowScrollBars -string "Always"

  # Disable smooth scrolling
  # (Uncomment if you’re on an older Mac that messes up the animation)
  #defaults write NSGlobalDomain NSScrollAnimationEnabled -bool false

  # Disable opening and closing window animations
  #defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false

  # Increase window resize speed for Cocoa applications
  defaults write NSGlobalDomain NSWindowResizeTime -float 0.001

  # Expand save panel by default
  defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true

  # Expand print panel by default
  defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true

  # Save to disk (not to iCloud) by default
  defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

  # Automatically quit printer app once the print jobs complete
  defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

  # Disable the “Are you sure you want to open this application?” dialog
  defaults write com.apple.LaunchServices LSQuarantine -bool false

  # Display ASCII control characters using caret notation in standard text views
  # Try e.g. `cd /tmp; unidecode "\x{0000}" > cc.txt; open -e cc.txt`
  defaults write NSGlobalDomain NSTextShowsControlCharacters -bool true

  # Disable Resume system-wide
  defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool false

  # Disable automatic termination of inactive apps
  defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true

  # Disable the crash reporter
  #defaults write com.apple.CrashReporter DialogType -string "none"

  # Set Help Viewer windows to non-floating mode
  defaults write com.apple.helpviewer DevMode -bool true

  # Fix for the ancient UTF-8 bug in QuickLook (http://mths.be/bbo)
  # Commented out, as this is known to cause problems when saving files in
  # Adobe Illustrator CS5 :(
  #echo "0x08000100:0" > ~/.CFUserTextEncoding

  # Reveal IP address, hostname, OS version, etc. when clicking the clock
  # in the login window
  sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName

  # Restart automatically if the computer freezes
  systemsetup -setrestartfreeze on

  # Never go into computer sleep mode
  systemsetup -setcomputersleep Off > /dev/null

  # Check for software updates daily, not just once per week
  defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1

  # Disable Notification Center and remove the menu bar icon
  launchctl unload -w /System/Library/LaunchAgents/com.apple.notificationcenterui.plist

  ###############################################################################
  # Trackpad, mouse, keyboard, Bluetooth accessories, and input #
  ###############################################################################

  # Trackpad: enable tap to click for this user and for the login screen
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
  defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Trackpad: map bottom right corner to right-click
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 2
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
  defaults -currentHost write NSGlobalDomain com.apple.trackpad.trackpadCornerClickBehavior -int 1
  defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true

  # Trackpad: swipe between pages with three fingers
  defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool true
  defaults -currentHost write NSGlobalDomain com.apple.trackpad.threeFingerHorizSwipeGesture -int 1
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture -int 1

  # Disable “natural” (Lion-style) scrolling
  #defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false

  # Increase sound quality for Bluetooth headphones/headsets
  defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 40

  # Enable full keyboard access for all controls
  # (e.g. enable Tab in modal dialogs)
  defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

  # Enable access for assistive devices
  echo -n 'a' | sudo tee /private/var/db/.AccessibilityAPIEnabled > /dev/null 2>&1
  sudo chmod 444 /private/var/db/.AccessibilityAPIEnabled
  # TODO: avoid GUI password prompt somehow (http://apple.stackexchange.com/q/60476/4408)
  #sudo osascript -e 'tell application "System Events" to set UI elements enabled to true'

  # Use scroll gesture with the Ctrl (^) modifier key to zoom
  defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
  defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144
  # Follow the keyboard focus while zoomed in
  defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true

  # Disable press-and-hold for keys in favor of key repeat
  defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

  # Set a blazingly fast keyboard repeat rate
  defaults write NSGlobalDomain KeyRepeat -int 0

  # Automatically illuminate built-in MacBook keyboard in low light
  defaults write com.apple.BezelServices kDim -bool true
  # Turn off keyboard illumination when computer is not used for 5 minutes
  defaults write com.apple.BezelServices kDimTime -int 300

  # Set language and text formats
  # Note: if you’re in the US, replace `EUR` with `USD`, `Centimeters` with
  # `Inches`, `en_GB` with `en_US`, and `true` with `false`.
  defaults write NSGlobalDomain AppleLanguages -array "es" "en" "nl"
  defaults write NSGlobalDomain AppleLocale -string "es_ES@currency=EUR"
  #defaults write NSGlobalDomain AppleLocale -string "en_GB@currency=EUR"
  defaults write NSGlobalDomain AppleMeasurementUnits -string "Centimeters"
  defaults write NSGlobalDomain AppleMetricUnits -bool true

  # Set the timezone; see `systemsetup -listtimezones` for other values
  systemsetup -settimezone "Europe/Madrid" > /dev/null

  # Disable auto-correct
  defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

  ###############################################################################
  # Screen #
  ###############################################################################

  # Require password immediately after sleep or screen saver begins
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0

  # Save screenshots to the desktop
  defaults write com.apple.screencapture location -string "$HOME/Desktop"

  # Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)
  defaults write com.apple.screencapture type -string "png"

  # Disable shadow in screenshots
  defaults write com.apple.screencapture disable-shadow -bool true

  # Enable subpixel font rendering on non-Apple LCDs
  defaults write NSGlobalDomain AppleFontSmoothing -int 2

  # Enable HiDPI display modes (requires restart)
  sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

  ###############################################################################
  # Finder #
  ###############################################################################

  # Finder: allow quitting via ⌘ + Q; doing so will also hide desktop icons
  #defaults write com.apple.finder QuitMenuItem -bool true

  # Finder: disable window animations and Get Info animations
  #defaults write com.apple.finder DisableAllAnimations -bool true

  # Show icons for hard drives, servers, and removable media on the desktop
  defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
  defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
  defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
  defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true

  # Finder: show hidden files by default
  defaults write com.apple.finder AppleShowAllFiles -bool true

  # Finder: show all filename extensions
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true

  # Finder: show status bar
  defaults write com.apple.finder ShowStatusBar -bool true

  # Finder: show path bar
  defaults write com.apple.finder ShowPathBar -bool true

  # Finder: allow text selection in Quick Look
  defaults write com.apple.finder QLEnableTextSelection -bool true

  # Display full POSIX path as Finder window title
  defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

  # When performing a search, search the current folder by default
  defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

  # Disable the warning when changing a file extension
  defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

  # Enable spring loading for directories
  defaults write NSGlobalDomain com.apple.springing.enabled -bool true

  # Remove the spring loading delay for directories
  defaults write NSGlobalDomain com.apple.springing.delay -float 0

  # Avoid creating .DS_Store files on network volumes
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

  # Disable disk image verification
  defaults write com.apple.frameworks.diskimages skip-verify -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-locked -bool true
  defaults write com.apple.frameworks.diskimages skip-verify-remote -bool true

  # Automatically open a new Finder window when a volume is mounted
  defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
  defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
  defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true

  # Show item info near icons on the desktop and in other icon views
  /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:showItemInfo true" ~/Library/Preferences/com.apple.finder.plist

  # Show item info to the right of the icons on the desktop
  /usr/libexec/PlistBuddy -c "Set DesktopViewSettings:IconViewSettings:labelOnBottom false" ~/Library/Preferences/com.apple.finder.plist

  # Enable snap-to-grid for icons on the desktop and in other icon views
  /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist

  # Increase grid spacing for icons on the desktop and in other icon views
  #/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:gridSpacing 100" ~/Library/Preferences/com.apple.finder.plist
  #/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 100" ~/Library/Preferences/com.apple.finder.plist
  #/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:gridSpacing 100" ~/Library/Preferences/com.apple.finder.plist

  # Increase the size of icons on the desktop and in other icon views
  #/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:iconSize 80" ~/Library/Preferences/com.apple.finder.plist
  #/usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:iconSize 80" ~/Library/Preferences/com.apple.finder.plist
  #/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:iconSize 80" ~/Library/Preferences/com.apple.finder.plist

  # Use column view in all Finder windows by default
  # Four-letter codes for the other view modes: `icnv`, `clmv`, `Flwv`
  #defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  defaults write com.apple.finder FXPreferredViewStyle -string "clmv"

  # Disable the warning before emptying the Trash
  defaults write com.apple.finder WarnOnEmptyTrash -bool false

  # Empty Trash securely by default
  defaults write com.apple.finder EmptyTrashSecurely -bool true

  # Enable AirDrop over Ethernet and on unsupported Macs running Lion
  defaults write com.apple.NetworkBrowser BrowseAllInterfaces -bool true

  # Enable the MacBook Air SuperDrive on any Mac
  sudo nvram boot-args="mbasd=1"

  # Show the ~/Library folder
  chflags nohidden ~/Library

  # Remove Dropbox’s green checkmark icons in Finder
  #file=/Applications/Dropbox.app/Contents/Resources/check.icns
  #[ -e "$file" ] && mv -f "$file" "$file.bak"
  #unset file

  ###############################################################################
  # Dock, Dashboard, and hot corners #
  ###############################################################################

  # Enable highlight hover effect for the grid view of a stack (Dock)
  defaults write com.apple.dock mouse-over-hilite-stack -bool true

  # Set the icon size of Dock items to 36 pixels
  defaults write com.apple.dock tilesize -int 36

  # Enable spring loading for all Dock items
  defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true

  # Show indicator lights for open applications in the Dock
  defaults write com.apple.dock show-process-indicators -bool true

  # Wipe all (default) app icons from the Dock
  # This is only really useful when setting up a new Mac, or if you don’t use
  # the Dock to launch apps.
  #defaults write com.apple.dock persistent-apps -array

  # Don’t animate opening applications from the Dock
  #defaults write com.apple.dock launchanim -bool false

  # Speed up Mission Control animations
  defaults write com.apple.dock expose-animation-duration -float 0.1

  # Don’t group windows by application in Mission Control
  # (i.e. use the old Exposé behavior instead)
  defaults write com.apple.dock expose-group-by-app -bool false

  # Don’t show Dashboard as a Space
  defaults write com.apple.dock dashboard-in-overlay -bool true

  # Disable Dashboard
  defaults write com.apple.dashboard mcx-disabled -bool true

  # Remove the auto-hiding Dock delay
  defaults write com.apple.dock autohide-delay -float 0
  # Remove the animation when hiding/showing the Dock
  #defaults write com.apple.dock autohide-time-modifier -float 0

  # Enable the 2D Dock
  #defaults write com.apple.dock no-glass -bool true

  # Automatically hide and show the Dock
  defaults write com.apple.dock autohide -bool true

  # Make Dock icons of hidden applications translucent
  defaults write com.apple.dock showhidden -bool true

  # Reset Launchpad
  find ~/Library/Application\ Support/Dock -name "*.db" -maxdepth 1 -delete

  # Add iOS Simulator to Launchpad
  sudo ln -s /Applications/Xcode.app/Contents/Applications/iPhone\ Simulator.app /Applications/iOS\ Simulator.app

  # Add a spacer to the left side of the Dock (where the applications are)
  #defaults write com.apple.dock persistent-apps -array-add '{tile-data={}; tile-type="spacer-tile";}'
  # Add a spacer to the right side of the Dock (where the Trash is)
  #defaults write com.apple.dock persistent-others -array-add '{tile-data={}; tile-type="spacer-tile";}'

  # Hot corners
  # Possible values:
  # 0: no-op
  # 2: Mission Control
  # 3: Show application windows
  # 4: Desktop
  # 5: Start screen saver
  # 6: Disable screen saver
  # 7: Dashboard
  # 10: Put display to sleep
  # 11: Launchpad
  # 12: Notification Center
  # Top left screen corner → Mission Control
  defaults write com.apple.dock wvous-tl-corner -int 2
  defaults write com.apple.dock wvous-tl-modifier -int 0
  # Top right screen corner → Show application windows
  defaults write com.apple.dock wvous-tr-corner -int 3
  defaults write com.apple.dock wvous-tr-modifier -int 0
  # Bottom left screen corner → Desktop
  defaults write com.apple.dock wvous-bl-corner -int 4
  defaults write com.apple.dock wvous-bl-modifier -int 0
  # Bottom right screen corner → Notification center
  defaults write com.apple.dock wvous-br-corner -int 12
  defaults write com.apple.dock wvous-br-modifier -int 0

  ###############################################################################
  # Safari & WebKit #
  ###############################################################################

  # Set Safari’s home page to `about:blank` for faster loading
  defaults write com.apple.Safari HomePage -string "about:blank"

  # Prevent Safari from opening ‘safe’ files automatically after downloading
  defaults write com.apple.Safari AutoOpenSafeDownloads -bool false

  # Allow hitting the Backspace key to go to the previous page in history
  defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled -bool true

  # Hide Safari’s bookmarks bar by default
  defaults write com.apple.Safari ShowFavoritesBar -bool false

  # Disable Safari’s thumbnail cache for History and Top Sites
  defaults write com.apple.Safari DebugSnapshotsUpdatePolicy -int 2

  # Enable Safari’s debug menu
  defaults write com.apple.Safari IncludeInternalDebugMenu -bool true

  # Make Safari’s search banners default to Contains instead of Starts With
  defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false

  # Remove useless icons from Safari’s bookmarks bar
  defaults write com.apple.Safari ProxiesInBookmarksBar "()"

  # Enable the Develop menu and the Web Inspector in Safari
  defaults write com.apple.Safari IncludeDevelopMenu -bool true
  defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
  defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true

  # Add a context menu item for showing the Web Inspector in web views
  defaults write NSGlobalDomain WebKitDeveloperExtras -bool true

  ###############################################################################
  # iTunes (pre-iTunes 11 only) #
  ###############################################################################

  # Disable the iTunes store link arrows
  defaults write com.apple.iTunes show-store-link-arrows -bool false

  # Disable the Genius sidebar in iTunes
  defaults write com.apple.iTunes disableGeniusSidebar -bool true

  # Disable radio stations in iTunes
  defaults write com.apple.iTunes disableRadio -bool true

  # Make ⌘ + F focus the search input in iTunes
  # To use these commands in another language, browse iTunes’s package contents,
  # open `Contents/Resources/your-language.lproj/Localizable.strings`, and look
  # for `kHiddenMenuItemTargetSearch`.
  defaults write com.apple.iTunes NSUserKeyEquivalents -dict-add "Target Search Field" "@F"

  ###############################################################################
  # Mail #
  ###############################################################################
  # Disable send and reply animations in Mail.app
  #defaults write com.apple.mail DisableReplyAnimations -bool true
  #defaults write com.apple.mail DisableSendAnimations -bool true

  # Copy email addresses as `foo@example.com` instead of `Foo Bar <foo@example.com>` in Mail.app
  defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false

  # Add the keyboard shortcut ⌘ + Enter to send an email in Mail.app
  defaults write com.apple.mail NSUserKeyEquivalents -dict-add "Send" "@\\U21a9"

  ###############################################################################
  # Terminal #
  ###############################################################################

  # Only use UTF-8 in Terminal.app
  defaults write com.apple.terminal StringEncodings -array 4

### TODO ###
  # Use a modified version of the Pro theme by default in Terminal.app
  #open "$HOME/init/Mathias.terminal"
  #sleep 1 # Wait a bit to make sure the theme is loaded
  #defaults write com.apple.terminal "Default Window Settings" -string "Mathias"
  #defaults write com.apple.terminal "Startup Window Settings" -string "Mathias"

  # Enable “focus follows mouse” for Terminal.app and all X11 apps
  # i.e. hover over a window and start typing in it without clicking first
  #defaults write com.apple.terminal FocusFollowsMouse -bool true
  #defaults write org.x.X11 wm_ffm -bool true

  ###############################################################################
  # Time Machine #
  ###############################################################################

  # Prevent Time Machine from prompting to use new hard drives as backup volume
  defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

  # Disable local Time Machine backups
  #hash tmutil &> /dev/null && sudo tmutil disablelocal

  ###############################################################################
  # Address Book, Dashboard, iCal, TextEdit, and Disk Utility #
  ###############################################################################

  # Enable the debug menu in Address Book
  defaults write com.apple.addressbook ABShowDebugMenu -bool true

  # Enable Dashboard dev mode (allows keeping widgets on the desktop)
  defaults write com.apple.dashboard devmode -bool true

  # Enable the debug menu in iCal (pre-10.8)
  defaults write com.apple.iCal IncludeDebugMenu -bool true

  # Use plain text mode for new TextEdit documents
  defaults write com.apple.TextEdit RichText -int 0
  # Open and save files as UTF-8 in TextEdit
  defaults write com.apple.TextEdit PlainTextEncoding -int 4
  defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4

  # Enable the debug menu in Disk Utility
  defaults write com.apple.DiskUtility DUDebugMenuEnabled -bool true
  defaults write com.apple.DiskUtility advanced-image-options -bool true

  ###############################################################################
  # Mac App Store #
  ###############################################################################

  # Enable the WebKit Developer Tools in the Mac App Store
  defaults write com.apple.appstore WebKitDeveloperExtras -bool true

  # Enable Debug Menu in the Mac App Store
  defaults write com.apple.appstore ShowDebugMenu -bool true

  ###############################################################################
  # Google Chrome & Google Chrome Canary #
  ###############################################################################

  # Allow installing user scripts via GitHub or Userscripts.org
  #defaults write com.google.Chrome ExtensionInstallSources -array "https://*.github.com/*" "http://userscripts.org/*"
  #defaults write com.google.Chrome.canary ExtensionInstallSources -array "https://*.github.com/*" "http://userscripts.org/*"

  ###############################################################################
  # SizeUp.app #
  ###############################################################################

  # Start SizeUp at login
  defaults write com.irradiatedsoftware.SizeUp StartAtLogin -bool true

  # Don’t show the preferences window on next start
  defaults write com.irradiatedsoftware.SizeUp ShowPrefsOnNextStart -bool false

  ###############################################################################
  # Transmission.app #
  ###############################################################################

  # Use `~/Documents/Torrents` to store incomplete downloads
  defaults write org.m0k.transmission UseIncompleteDownloadFolder -bool true
  defaults write org.m0k.transmission IncompleteDownloadFolder -string "${HOME}/Documents/Torrents"

# Don’t prompt for confirmation before downloading
  defaults write org.m0k.transmission DownloadAsk -bool false

  # Trash original torrent files
  defaults write org.m0k.transmission DeleteOriginalTorrent -bool true

  # Hide the donate message
  defaults write org.m0k.transmission WarningDonate -bool false
  # Hide the legal disclaimer
  defaults write org.m0k.transmission WarningLegal -bool false

  ###############################################################################
  # Twitter.app #
  ###############################################################################

  # Disable smart quotes as it’s annoying for code tweets
  #defaults write com.twitter.twitter-mac AutomaticQuoteSubstitutionEnabled -bool false

  # Show the app window when clicking the menu icon
  #defaults write com.twitter.twitter-mac MenuItemBehavior -int 1

  # Enable the hidden ‘Develop’ menu
  #defaults write com.twitter.twitter-mac ShowDevelopMenu -bool true

  # Open links in the background
  #defaults write com.twitter.twitter-mac openLinksInBackground -bool true

  # Allow closing the ‘new tweet’ window by pressing `Esc`
  #defaults write com.twitter.twitter-mac ESCClosesComposeWindow -bool true

  # Show full names rather than Twitter handles
  #defaults write com.twitter.twitter-mac ShowFullNames -bool true

  # Hide the app in the background if it’s not the front-most window
  #defaults write com.twitter.twitter-mac HideInBackground -bool true

  ###############################################################################
  # Kill affected applications #
  ###############################################################################
  #"Twitter"
  for app in "Address Book" "Calendar" "Contacts" "Dashboard" "Dock" "Finder" \
             "Mail" "Safari" "SizeUp" "SystemUIServer" "Terminal" "Transmission" \
             "iCal" "iTunes"; do
    killall "$app" > /dev/null 2>&1
  done
  log_ok "Done applying OSX Tweakings. ${attention}Note that some of these changes require a logout/restart to take effect"
      
}


