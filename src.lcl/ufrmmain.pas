{
  This file contains the basic implementation of a GUI frontend for Petris - YATC.

  Copyright (C) 2018 ENY (eny_fpc@ziggo.nl)

  This source is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
  License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
  version.

  This code is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
  warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
  details.

  A copy of the GNU General Public License is available on the World Wide Web at
  <http://www.gnu.org/copyleft/gpl.html>. You can also obtain it by writing to the Free Software Foundation, Inc., 51
  Franklin Street - Fifth Floor, Boston, MA 02110-1335, USA.
}
unit ufrmMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls, Grids, StdCtrls, Buttons, PetrisEngine,
  Types, LCLType;

type

  { TForm1 }

  TForm1 = class(TForm)
    dgPetris: TDrawGrid;
    ilMinos: TImageList;
    Image1: TImage;
    Panel1: TPanel;
    Panel10: TPanel;
    Panel3: TPanel;
    Panel2: TPanel;
    Panel4: TPanel;
    Panel5: TPanel;
    Panel6: TPanel;
    Panel7: TPanel;
    Panel8: TPanel;
    Panel9: TPanel;
    pnScore: TPanel;
    pbPipeline: TPaintBox;
    pnStart: TPanel;
    tmrPhase: TTimer;

    procedure dgPetrisDrawCell(Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure pbPipelinePaint(Sender: TObject);
    procedure pnStartClick(Sender: TObject);
    procedure tmrEnded(Sender: TObject);

  private
    FGame: TPetrisGame;
    FFallFast: boolean;

    procedure StartGame;

    procedure RepaintBoard      ( pGame: TPetrisGame );
    procedure PipelineChanged   ( pGame: TPetrisGame );
    procedure EnterFallingPhase ( pGame: TPetrisGame );
    procedure EnterLockPhase    ( pGame: TPetrisGame );
    procedure EndGame           ( pGame: TPetrisGame );
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormDestroy(Sender: TObject);
begin
  // Clean up a possible running game
  FGame.Free;
end;

procedure TForm1.dgPetrisDrawCell(Sender: TObject; aCol, aRow: Integer; aRect: TRect; aState: TGridDrawState);
var clr: TColor;
    col, row: integer;
    idx: integer;
begin
  // Make sure there is something to draw from
  if not assigned(FGame) then exit;

  // Translate grid cell coordinates to game matrix coordinates
  col := aCol + 1;
  row := dgPetris.RowCount - aRow;
  if FGame.Mino[col,row].CellState <> pssOpen then
    begin
      idx := ord(FGame.Mino[col,row].MinoType);
      ilMinos.Draw(dgPetris.Canvas, aRect.Left, aRect.Top, idx);
    end
  else
    begin
      clr := clBlack;
      dgPetris.Canvas.Brush.Color := clr;
      dgPEtris.Canvas.FillRect(aRect);
    end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  panel10.Caption := ' CuUp = rotate'     + LineEnding +
                     ' CuDn = down fast'  + LineEnding +
                     ' CuLt = move left'  + LineEnding +
                     ' CuRt = move right' + LineEnding +
                     ' Space = lock'
end;

procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // If the game is running handle the specific game keys
  if assigned(FGame) then
    begin
      if Key = VK_LEFT then
        FGame.MoveLeft;
      if Key = VK_RIGHT then
        FGame.MoveRight;
      if Key = VK_UP then
        FGame.RotateClockwise;
      if Key = VK_DOWN then
      begin
        FFallFast := true;
        if FGAme.GameState = gsFalling then
          tmrEnded(tmrPhase);
      end;
      if Key = VK_SPACE then
        FGame.DropBlockDown;
      Key := 0
    end
  else
    if Key = VK_S then // Else start a game when S is pressed
      StartGame;
end;

procedure TForm1.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // In case the DOWN key was pressed i.e. fast falling enabled, disable it here
  if Key = VK_DOWN then
    FFallFast := false;
end;

procedure TForm1.pbPipelinePaint(Sender: TObject);
var pb     : TPaintBox;
    i      : integer;
    TopLeft: TPoint;
    WorldXY: TPoint;
begin
  // Draw background
  pb := Sender as TPaintBox;
  pb.Canvas.Brush.Color := clBlack;
  pb.Canvas.FillRect(0,0, pb.Width,pb.Height);

  // Game running?
  if assigned(FGame) then
  begin
    // Calculate top left position of the first minos (0,0) in the paintbox
    topleft.y := pbPipeline.Height div 2 - 24;
    case FGame.PipeLine.PetriminoType of
      pmtO: topleft.x := pbPipeline.Width div 2 - 48;
      pmtI: topleft   := point(pbPipeline.Width div 2 - 48, pbPipeline.Height div 2 - 36);
    else
      topleft.x := pbPipeline.Width div 2 - 36;
    end;

    // Now draw all 4 minos of the current petrimino
    for i := 0 to 3 do
    begin
      WorldXY := Point( TopLeft.X + FGame.PipeLine.Position(i).x * 24,
                        TopLeft.Y - FGame.PipeLine.Position(i).y * 24);
      ilMinos.Draw(pb.Canvas, WorldXY.x, WorldXY.y, ord(FGame.PipeLine.PetriminoType));
    end;
  end;
end;

procedure TForm1.pnStartClick(Sender: TObject);
begin
  StartGame;
end;

procedure TForm1.EnterFallingPhase(pGame: TPetrisGame);
var NewInt: integer;
begin
  // Disable all possible previous timings - the game has triggerd a new falling phase
  tmrPhase.Enabled := false;

  // Falling has started - the timer depends on the level: the higher
  // the level the faster the petriminos fall.
  // When the DOWN key is pressed then falling goes even faster.
  NewInt := 500 - ( (pGame.Level-1) * 40 );
  if FFallFast then
    NewInt := NewInt div 10;
  if NewInt < 5 then NewInt := 5;
  tmrPhase.Interval := NewInt;

  // Start the timer
  tmrPhase.Enabled := true;
end;

procedure TForm1.EnterLockPhase(pGame: TPetrisGame);
begin
  // During locking the game waits a small amount of time during which the player
  // can still press keys to move the block. After that time the block locks and the next
  // comes falling down.
  tmrPhase.Enabled := false;
  tmrPhase.Interval := 250;
  tmrPhase.Enabled := true;
end;

procedure TForm1.tmrEnded(Sender: TObject);
begin
  // Stop the timer and let the game handle the next action
  (Sender as TTimer).Enabled := false;
  FGame.Next;
end;

procedure TForm1.StartGame;
begin
  // If the game is already running then do not start again
  if assigned(FGame) then exit;

  // Update GUI - disable start button panel
  pnStart.Visible := false;
  self.SetFocus; // Make sure that the drawgrid does not have the focus

  // Let's start with a new set of petriminos
  Randomize;

  // Set up a new game
  FGame := TPetrisGame.Create;
  FGame.OnMatrixChanged     := @RepaintBoard;
  FGame.OnPipelineChanged   := @PipelineChanged;
  FGame.OnEnterFallingPhase := @EnterFallingPhase;
  FGame.OnEnterLockPhase    := @EnterLockPhase;
  FGame.OnEndGame           := @EndGame;

  // Actual start
  FGame.Next;
end;

procedure TForm1.RepaintBoard(pGame: TPetrisGame);
begin
  dgPetris.Repaint;
  pnScore.Caption := IntToStr(pGame.Level) + ':' + IntToSTr(pGame.Score);
  Panel1.Caption := 'O: ' + IntToStr(pGame.PetriminoCount( pmtO ));
  Panel4.Caption := 'I: ' + IntToStr(pGame.PetriminoCount( pmtI ));
  Panel5.Caption := 'T: ' + IntToStr(pGame.PetriminoCount( pmtT ));
  Panel6.Caption := 'L: ' + IntToStr(pGame.PetriminoCount( pmtL ));
  Panel7.Caption := 'J: ' + IntToStr(pGame.PetriminoCount( pmtJ ));
  Panel8.Caption := 'S: ' + IntToStr(pGame.PetriminoCount( pmtS ));
  Panel9.Caption := 'Z: ' + IntToStr(pGame.PetriminoCount( pmtZ ));
end;

procedure TForm1.PipelineChanged(pGame: TPetrisGame);
begin
  pbPipeline.Repaint;
end;

procedure TForm1.EndGame(pGame: TPetrisGame);
begin
  tmrPhase.Enabled := false;
  pGame.Free;
  FGame := nil;
  ShowMessage('The game has ended - Ready to give it another try?');
  pnStart.Visible := true;

  // Clear visible elements
  dgPetris.Repaint;
  pbPipeline.Repaint;
end;

end.

