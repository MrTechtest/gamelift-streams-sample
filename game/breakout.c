/*
 * Sample game for Amazon GameLift Streams (Ubuntu 22.04 native Linux runtime)
 * ---------------------------------------------------------------------------
 * A tiny, self-contained "Breakout" clone written with SDL2.
 *
 * Controls:
 *   Left / Right arrow keys (or A / D) : move the paddle
 *   Space                              : launch the ball / restart after game over
 *   Esc                                : quit
 *
 * Rendering uses the SDL2 accelerated renderer (OpenGL under the hood), which
 * Amazon GameLift Streams captures on the Linux runtime. The window is created
 * as full-screen-desktop so the whole frame is streamed.
 *
 * This file is intentionally dependency-light: only SDL2 is required.
 */
#include <SDL2/SDL.h>
#include <stdbool.h>
#include <stdlib.h>
#include <math.h>

#define VW 1280          /* logical (virtual) render width  */
#define VH 720           /* logical (virtual) render height */

#define PADDLE_W 160
#define PADDLE_H 18
#define PADDLE_Y (VH - 60)
#define PADDLE_SPEED 900.0f

#define BALL_SIZE 16
#define BALL_SPEED 520.0f

#define COLS 11
#define ROWS 6
#define BRICK_GAP 8
#define BRICK_TOP 80
#define BRICK_H 30

typedef struct { float x, y, vx, vy; } Ball;
typedef struct { SDL_FRect rect; int alive; int r, g, b; } Brick;

static void reset_bricks(Brick *bricks) {
    int total_gap = BRICK_GAP * (COLS + 1);
    float bw = (float)(VW - total_gap) / COLS;
    for (int row = 0; row < ROWS; row++) {
        for (int col = 0; col < COLS; col++) {
            Brick *b = &bricks[row * COLS + col];
            b->rect.x = BRICK_GAP + col * (bw + BRICK_GAP);
            b->rect.y = BRICK_TOP + row * (BRICK_H + BRICK_GAP);
            b->rect.w = bw;
            b->rect.h = BRICK_H;
            b->alive = 1;
            /* pleasant per-row gradient */
            b->r = 60 + row * 30;
            b->g = 200 - row * 25;
            b->b = 230 - row * 20;
        }
    }
}

static void reset_ball(Ball *ball) {
    ball->x = VW / 2.0f;
    ball->y = PADDLE_Y - 40;
    ball->vx = 0;
    ball->vy = 0;
}

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER) != 0) {
        SDL_Log("SDL_Init failed: %s", SDL_GetError());
        return 1;
    }

    /* Full-screen desktop so the entire streamed frame is the game. */
    SDL_Window *win = SDL_CreateWindow(
        "GameLift Streams Sample - Breakout",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        VW, VH,
        SDL_WINDOW_FULLSCREEN_DESKTOP | SDL_WINDOW_SHOWN);
    if (!win) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    SDL_Renderer *ren = SDL_CreateRenderer(
        win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!ren) {
        /* fall back to software rendering if no GPU accel is exposed */
        ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE);
    }
    if (!ren) {
        SDL_Log("SDL_CreateRenderer failed: %s", SDL_GetError());
        SDL_DestroyWindow(win);
        SDL_Quit();
        return 1;
    }
    /* Keep a fixed logical resolution regardless of the real window size. */
    SDL_RenderSetLogicalSize(ren, VW, VH);
    SDL_ShowCursor(SDL_DISABLE);

    Brick bricks[COLS * ROWS];
    reset_bricks(bricks);

    float paddle_x = (VW - PADDLE_W) / 2.0f;
    Ball ball;
    reset_ball(&ball);
    bool ball_launched = false;

    int score = 0;
    int lives = 3;
    bool game_over = false;
    bool win_state = false;

    SDL_GameController *pad = NULL;
    for (int i = 0; i < SDL_NumJoysticks(); i++) {
        if (SDL_IsGameController(i)) { pad = SDL_GameControllerOpen(i); break; }
    }

    bool running = true;
    Uint64 prev = SDL_GetPerformanceCounter();
    const Uint64 freq = SDL_GetPerformanceFrequency();

    while (running) {
        /* ---- timing ---- */
        Uint64 now = SDL_GetPerformanceCounter();
        float dt = (float)(now - prev) / (float)freq;
        prev = now;
        if (dt > 0.05f) dt = 0.05f; /* clamp after stalls */

        /* ---- events ---- */
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) running = false;
            if (e.type == SDL_KEYDOWN) {
                SDL_Keycode k = e.key.keysym.sym;
                if (k == SDLK_ESCAPE) running = false;
                if (k == SDLK_SPACE) {
                    if (game_over || win_state) {
                        reset_bricks(bricks);
                        reset_ball(&ball);
                        ball_launched = false;
                        score = 0; lives = 3;
                        game_over = false; win_state = false;
                    } else if (!ball_launched) {
                        ball_launched = true;
                        ball.vx = BALL_SPEED * 0.35f;
                        ball.vy = -BALL_SPEED;
                    }
                }
            }
            if (e.type == SDL_CONTROLLERBUTTONDOWN &&
                e.cbutton.button == SDL_CONTROLLER_BUTTON_A && !ball_launched &&
                !game_over && !win_state) {
                ball_launched = true;
                ball.vx = BALL_SPEED * 0.35f;
                ball.vy = -BALL_SPEED;
            }
        }

        /* ---- input (held keys) ---- */
        const Uint8 *ks = SDL_GetKeyboardState(NULL);
        float dir = 0;
        if (ks[SDL_SCANCODE_LEFT] || ks[SDL_SCANCODE_A]) dir -= 1;
        if (ks[SDL_SCANCODE_RIGHT] || ks[SDL_SCANCODE_D]) dir += 1;
        if (pad) {
            if (SDL_GameControllerGetButton(pad, SDL_CONTROLLER_BUTTON_DPAD_LEFT)) dir -= 1;
            if (SDL_GameControllerGetButton(pad, SDL_CONTROLLER_BUTTON_DPAD_RIGHT)) dir += 1;
            Sint16 ax = SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTX);
            if (ax < -8000) dir -= 1; else if (ax > 8000) dir += 1;
        }

        if (!game_over && !win_state) {
            paddle_x += dir * PADDLE_SPEED * dt;
            if (paddle_x < 0) paddle_x = 0;
            if (paddle_x > VW - PADDLE_W) paddle_x = VW - PADDLE_W;

            if (!ball_launched) {
                ball.x = paddle_x + PADDLE_W / 2.0f;
                ball.y = PADDLE_Y - BALL_SIZE;
            } else {
                ball.x += ball.vx * dt;
                ball.y += ball.vy * dt;

                /* walls */
                if (ball.x < 0) { ball.x = 0; ball.vx = -ball.vx; }
                if (ball.x > VW - BALL_SIZE) { ball.x = VW - BALL_SIZE; ball.vx = -ball.vx; }
                if (ball.y < 0) { ball.y = 0; ball.vy = -ball.vy; }

                /* paddle */
                SDL_FRect pr = { paddle_x, PADDLE_Y, PADDLE_W, PADDLE_H };
                SDL_FRect br = { ball.x, ball.y, BALL_SIZE, BALL_SIZE };
                if (br.y + br.h >= pr.y && br.y + br.h <= pr.y + pr.h + 12 &&
                    br.x + br.h >= pr.x && br.x <= pr.x + pr.w && ball.vy > 0) {
                    ball.vy = -fabsf(ball.vy);
                    float hit = (ball.x + BALL_SIZE / 2.0f) - (paddle_x + PADDLE_W / 2.0f);
                    ball.vx = (hit / (PADDLE_W / 2.0f)) * BALL_SPEED;
                }

                /* bricks */
                for (int i = 0; i < COLS * ROWS; i++) {
                    if (!bricks[i].alive) continue;
                    SDL_FRect *rr = &bricks[i].rect;
                    if (ball.x + BALL_SIZE > rr->x && ball.x < rr->x + rr->w &&
                        ball.y + BALL_SIZE > rr->y && ball.y < rr->y + rr->h) {
                        bricks[i].alive = 0;
                        score += 10;
                        ball.vy = -ball.vy;
                        break;
                    }
                }

                /* fell below paddle */
                if (ball.y > VH) {
                    lives--;
                    ball_launched = false;
                    reset_ball(&ball);
                    if (lives <= 0) game_over = true;
                }

                /* win check */
                int remaining = 0;
                for (int i = 0; i < COLS * ROWS; i++) remaining += bricks[i].alive;
                if (remaining == 0) win_state = true;
            }
        }

        /* ---- render ---- */
        SDL_SetRenderDrawColor(ren, 14, 18, 34, 255);
        SDL_RenderClear(ren);

        /* bricks */
        for (int i = 0; i < COLS * ROWS; i++) {
            if (!bricks[i].alive) continue;
            SDL_SetRenderDrawColor(ren, bricks[i].r, bricks[i].g, bricks[i].b, 255);
            SDL_RenderFillRectF(ren, &bricks[i].rect);
        }

        /* paddle */
        SDL_SetRenderDrawColor(ren, 240, 240, 255, 255);
        SDL_FRect pr = { paddle_x, PADDLE_Y, PADDLE_W, PADDLE_H };
        SDL_RenderFillRectF(ren, &pr);

        /* ball */
        SDL_SetRenderDrawColor(ren, 255, 210, 80, 255);
        SDL_FRect br = { ball.x, ball.y, BALL_SIZE, BALL_SIZE };
        SDL_RenderFillRectF(ren, &br);

        /* simple score / lives bar (drawn as little rectangles, no font dep) */
        SDL_SetRenderDrawColor(ren, 90, 200, 250, 255);
        for (int i = 0; i < score / 10 && i < 60; i++) {
            SDL_FRect s = { 20 + i * 8, 20, 6, 14 };
            SDL_RenderFillRectF(ren, &s);
        }
        SDL_SetRenderDrawColor(ren, 250, 90, 110, 255);
        for (int i = 0; i < lives; i++) {
            SDL_FRect l = { (float)(VW - 40 - i * 34), 20, 24, 24 };
            SDL_RenderFillRectF(ren, &l);
        }

        /* dim overlay for game over / win */
        if (game_over || win_state) {
            SDL_SetRenderDrawBlendMode(ren, SDL_BLENDMODE_BLEND);
            SDL_SetRenderDrawColor(ren, 0, 0, 0, 150);
            SDL_FRect full = { 0, 0, VW, VH };
            SDL_RenderFillRectF(ren, &full);
            /* big colored banner: green=win, red=over */
            if (win_state) SDL_SetRenderDrawColor(ren, 80, 220, 120, 255);
            else SDL_SetRenderDrawColor(ren, 230, 80, 90, 255);
            SDL_FRect banner = { VW / 2.0f - 220, VH / 2.0f - 40, 440, 80 };
            SDL_RenderFillRectF(ren, &banner);
        }

        SDL_RenderPresent(ren);
    }

    if (pad) SDL_GameControllerClose(pad);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
}
