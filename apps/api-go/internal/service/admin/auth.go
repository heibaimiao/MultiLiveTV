package admin

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const accessTokenTTL = 8 * time.Hour

type Service struct {
	username  string
	password  string
	jwtSecret []byte
}

func NewService(username, password, jwtSecret string) *Service {
	return &Service{
		username:  username,
		password:  password,
		jwtSecret: []byte(jwtSecret),
	}
}

type Claims struct {
	Role     string `json:"role"`
	Username string `json:"username"`
	jwt.RegisteredClaims
}

type LoginResult struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int64  `json:"expires_in"`
}

func (s *Service) Login(username, password string) (*LoginResult, error) {
	if username != s.username || password != s.password {
		return nil, errors.New("invalid credentials")
	}
	now := time.Now()
	claims := Claims{
		Role:     "admin",
		Username: username,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(now.Add(accessTokenTTL)),
			IssuedAt:  jwt.NewNumericDate(now),
			Subject:   username,
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	access, err := token.SignedString(s.jwtSecret)
	if err != nil {
		return nil, err
	}
	return &LoginResult{
		AccessToken: access,
		ExpiresIn:   int64(accessTokenTTL.Seconds()),
	}, nil
}

func (s *Service) ParseToken(tokenStr string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (any, error) {
		return s.jwtSecret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid || claims.Role != "admin" {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}
